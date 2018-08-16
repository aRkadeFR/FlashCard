{-# LANGUAGE QuasiQuotes, DataKinds, DeriveGeneric, DeriveDataTypeable, FlexibleInstances, TypeOperators, TemplateHaskell, MultiParamTypeClasses #-}

module User
  ( User(..)
  , getNewToken
  , verifyToken
  , getSessionJWT
  , verifyJWT
  , updatePassword
  , getUser
  , getUserById
  )
  where

import Data.Swagger (ToSchema)
import Data.Aeson
import Data.Typeable
import Data.Convertible
import Database.HDBC
import Database.YeshQL.HDBC.SqlRow.Class
import Database.YeshQL.HDBC.SqlRow.TH
import Database.YeshQL.HDBC (yeshFile)
import GHC.Generics
import Servant.Elm (ElmType)

data User = User
  { userid    :: Int
  , username  :: String
  , email     :: String
  , lang      :: String
  } deriving (Eq, Generic, Show)
makeSqlRow ''User

instance ToSchema User
instance ToJSON User
instance FromJSON User
instance ElmType User

[yeshFile|src/sql/User.sql|]
