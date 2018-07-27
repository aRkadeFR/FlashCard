{-# LANGUAGE QuasiQuotes                #-}
{-# LANGUAGE TemplateHaskell            #-}
{-# LANGUAGE DataKinds                  #-}
{-# LANGUAGE DeriveGeneric              #-}
{-# LANGUAGE FlexibleContexts           #-}
{-# LANGUAGE FlexibleInstances          #-}
{-# LANGUAGE MultiParamTypeClasses      #-}
{-# LANGUAGE OverloadedStrings          #-}
{-# LANGUAGE ScopedTypeVariables        #-}
{-# LANGUAGE TypeFamilies               #-}
{-# LANGUAGE TypeOperators              #-}
{-# LANGUAGE UndecidableInstances       #-}
{-# LANGUAGE DeriveDataTypeable         #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}

module API
  ( runApp
  , CombinedAPI
  , userServer
  , UserAPI
  , WordAPI
  , wordServer
  )
  where

import Prelude hiding (Word)
import Data.Pool
import Data.Aeson
import Data.Swagger
import GHC.Generics
import Control.Lens
import Control.Monad.IO.Class (liftIO)
import Servant.API ((:<|>) ((:<|>)), (:>), BasicAuth, Get, Post, ReqBody, JSON, NoContent(..))
import Servant.API.BasicAuth (BasicAuthData (BasicAuthData))
import Database.HDBC (commit)
import Database.HDBC.PostgreSQL (Connection, begin)
import Network.Wai
import Network.Wai.Handler.Warp
import Network.Wai.Middleware.Cors
import Network.Wai.Middleware.RequestLogger (logStdoutDev)
import Servant
import Servant.Server
import Servant.Swagger
import Servant.Swagger.UI
import PostgreSQL (getAllWords, getLastWords, insertWord)
import Word (Word(..), wordConstructor)
import User (User(..))
import Auth


userServer :: User -> Server UserAPI
userServer user = return user

-- | API for the users
type UserAPI = Get '[JSON] User

pgRetrieveAllWords :: User -> Connection -> IO [Word]
pgRetrieveAllWords user conn = do
  listWords <- getAllWords user conn
  return $ map wordConstructor listWords

pgRetrieveLastWords :: User -> Connection -> IO [Word]
pgRetrieveLastWords user conn = do
  listWords <- getLastWords user conn
  return $ map wordConstructor listWords

-- | API for the words
type WordAPI = "all" :> Get '[JSON] [Word]
          :<|> "last" :> Get '[JSON] [Word]
          :<|> ReqBody '[JSON] Word :> Post '[JSON] NoContent

wordServer :: User -> Pool Connection -> Server WordAPI
wordServer user conns = retrieveAllWords
                   :<|> retrieveLastWords
                   :<|> postWord

  where retrieveAllWords :: Handler [Word]
        retrieveAllWords = do
          liftIO $ 
            withResource conns $ \conn -> do
              begin conn
              words <- pgRetrieveAllWords user conn
              commit conn
              return words

        retrieveLastWords :: Handler [Word]
        retrieveLastWords = do
          liftIO $ 
            withResource conns $ \conn -> do
              begin conn
              words <- pgRetrieveLastWords user conn
              commit conn
              return words

        postWord :: Word -> Handler NoContent
        postWord word = do
          liftIO $
            withResource conns $ \conn -> do
              begin conn
              insertWord (wordLanguage word) (wordWord word) (wordDefinition word) conn
              commit conn
              return ()
          return NoContent


-- | API for serving @swagger.json@.
type SwaggerAPI = "swagger.json" :> Get '[JSON] Swagger

-- | API for all objects
type CombinedAPI = "user" :> UserAPI
              :<|> "words" :> WordAPI

-- | Combined API of a Todo service with Swagger documentation.
type API = BasicAuth "words-realm" User :> CombinedAPI
      :<|> SwaggerSchemaUI "swagger-ui" "swagger.json"

combinedServer :: User -> Pool Connection -> Server CombinedAPI
combinedServer user conns = ( (userServer user) :<|> (wordServer user conns) )

apiServer :: Pool Connection -> Server API
apiServer conns =
  let authCombinedServer (user :: User) = (combinedServer user conns)
  in  (authCombinedServer :<|> swaggerSchemaUIServer apiSwagger)

api :: Proxy API
api = Proxy

-- | Swagger spec for Todo API.
apiSwagger :: Swagger
apiSwagger = toSwagger (Proxy :: Proxy CombinedAPI)
  & info.title        .~ "OuiCook API"
  & info.version      .~ "1.0"
  & info.description  ?~ "OuiCook is 100% API driven"
  & info.license      ?~ "MIT"

app :: Pool Connection -> Application
app conns = serveWithContext api basicAuthServerContext (apiServer conns)

corsPolicy :: CorsResourcePolicy
corsPolicy = CorsResourcePolicy {
    corsOrigins = Nothing
  , corsMethods = corsMethods simpleCorsResourcePolicy
  , corsRequestHeaders =["Authorization", "Content-Type"]
  , corsExposedHeaders = corsExposedHeaders simpleCorsResourcePolicy
  , corsMaxAge = corsMaxAge simpleCorsResourcePolicy
  , corsVaryOrigin = corsVaryOrigin simpleCorsResourcePolicy
  , corsRequireOrigin = False
  , corsIgnoreFailures = corsIgnoreFailures simpleCorsResourcePolicy
}

runApp :: Pool Connection -> IO ()
runApp conns = do
  Network.Wai.Handler.Warp.run 8080 (logStdoutDev . (cors $ const $ Just corsPolicy) $ (app conns))