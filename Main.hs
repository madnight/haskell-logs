{-# LANGUAGE CPP                 #-}
{-# LANGUAGE DeriveGeneric       #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeOperators       #-}
{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE RecordWildCards     #-}
{-# LANGUAGE TypeFamilies        #-}
{-# LANGUAGE LambdaCase          #-}
{-# LANGUAGE PatternSynonyms     #-}
{-# LANGUAGE OverloadedStrings   #-}


module Main where

#if MIN_VERSION_servant(0,10,0)
import Servant.Utils.Links
#endif

import           Network.URI                          ( parseURI
                                                      , parseRelativeReference
                                                      , pathSegments
                                                      )

import Text.Printf
import           Data.Proxy
import           Servant.API                   hiding (GET)
import           Data.List                            (isInfixOf)
import           Data.Aeson
import           Data.Aeson.Types
import qualified Data.Map                      as M
import           Data.Maybe
import           GHC.Generics
import           JavaScript.Web.XMLHttpRequest
import           Miso                          hiding (defaultOptions)
import           Miso.String                   hiding (last, splitAt, isInfixOf)
import           Prelude                       hiding (head, concat, unwords)
import           Control.Monad

replaceAtIndex n item ls = a ++ (item:b)
    where (a, (_:b)) = splitAt n ls

-- | Model
data Model =
  Model { info  :: Maybe APIInfo
        , uri   :: URI
         -- ^ current URI of application
        , query :: MisoString
        } deriving (Eq, Show)

-- | Action
data Action
  = FetchGitHub MisoString
  | SetGitHub APIInfo
  | SetQuery MisoString
  | HandleURI URI
  | ChangeURI URI
  | NoOp
  deriving (Show, Eq)


-- | Main entry point
main :: IO ()
main = do
   currentURI <- getCurrentURI
   print currentURI
   startApp
           App { model = Model { info = Nothing, query = "", uri = currentURI }
               , initialAction = NoOp
               , mountPoint = Nothing
               , ..
               }
    where
      update = updateModel
      events = defaultEvents
      subs   = [ uriSub HandleURI ]
      view   = viewModel
      mountPoint = Nothing


-- | Update your model
updateModel :: Action -> Model -> Effect Action Model

updateModel (FetchGitHub s) m = m <# do
  SetGitHub <$> getGitHubAPIInfo (query m)

updateModel (SetQuery q) m =
  noEff m { query = q }

updateModel (SetGitHub apiInfo) m =
  noEff m { info = Just apiInfo }

updateModel (ChangeURI u) m = m <# do
  pushURI u
  pure NoOp

updateModel (HandleURI u) m = m { uri = u } <# do
  pure NoOp

updateModel NoOp m =
  noEff m


-- | View function, with routing
viewModel :: Model -> View Action
viewModel model@Model {..}
    | "about" `isInfixOf` show uri = about
    | otherwise = view
  where
    url = uriparser . parseURI
    pager = read (last $ pathSegments uri) :: Integer

    about = div_ [ style_ $ M.fromList [
                  (pack "text-align", pack "center")
                , (pack "margin", pack "50px")
                ]
               ] [

        h1_ [class_ $ pack "title" ] [ text $ pack "Haskell IRC Log Search" ]
        ,
           case info of
          Nothing -> div_ attrs [ text $ pack "ABC" ]
          Just APIInfo{..} ->
            div_ [] [
               br_ [] []
               , th_ [] [ text $ ""]
               , table_ [ class_ $ pack "table is-striped" ] [
                 thead_ [] [td_ [] [i] | i <- ["Date", "Time", "User", "Post"]]
               , tbody_ [] $ results_ rows
                 ]
               ]
            ]

      where
        attrs = [ onClick $ FetchGitHub "  "
                , onMouseOver $ SetQuery (toMisoString $ "rowid+%3E+" ++ show pager ++ "+AND+rowid+%3C+" ++ show ((pager + 100)))
                , autofocus_ True
                , class_ $ pack "button is-large is-outlined"
                ] ++ [ disabled_ False | isJust info ]



    the404 = div_ [] [
            text "the 404 :("
          , button_ [ onClick goHome ] [ text "go home Y" ]
          ]

    view = div_ [ style_ $ M.fromList [
                  (pack "text-align", pack "center")
                , (pack "margin", pack "50px")
                ]
               ] [
        h1_ [class_ $ pack "title" ] [ text $ pack "Haskell IRC Log Search" ]

      , input_ attrs [
          text $ pack ""
          ]

      , case info of
          Nothing -> div_ [] [ text $ pack "" ]
          Just APIInfo{..} ->
            div_ [] [
               br_ [] []
               , th_ [] [ text
               $ pack ("Search Results (" ++ show (round query_ms) ++ " ms)")]
               , table_ [ class_ $ pack "table is-striped" ] [
                 thead_ [] [td_ [] [i] | i <- ["Date", "Time", "User", "Post"]]
               , tbody_ [] $ results_ rows
                 ]
               ]
            ]

           where
        attrs = [ onKeyDown $ \case
          EnterButton -> FetchGitHub "  "
          _           -> NoOp
                , onInput (\x -> SetQuery $ toMisoString $ "post+like+%22%25" ++ (printf "%s" (show x) :: String) ++ "%25%22+limit+14")
                , autofocus_ True
                , class_ $ pack "button is-large is-outlined"
                ] ++ [ disabled_ False | isJust info ]


pattern EnterButton :: KeyCode
pattern EnterButton = KeyCode 13

results_ :: [[MisoString]] -> [View action]
results_ (x:xs) = tr_ [] (tdd $ ircName x) : results_ xs
results_ _ = []

ircName :: [MisoString] -> [MisoString]
ircName (a:b:c:d) = a : b : concat ["<", c, ">"] : d

tdd :: [MisoString] -> [View action]
tdd (x:xs) = td_ [] [text $ x] : tdd xs
tdd _ = []

data APIInfo
  = APIInfo
  { database :: MisoString
  , rows :: [[MisoString]]
  , query_ms :: Float
  } deriving (Show, Eq, Generic)

instance FromJSON APIInfo where
  parseJSON = genericParseJSON defaultOptions { fieldLabelModifier = camelTo '_' }

getGitHubAPIInfo :: MisoString -> IO APIInfo
getGitHubAPIInfo q = do
  Just resp <- contents <$> xhrByteString req
  case eitherDecodeStrict resp :: Either String APIInfo of
    Left s -> error s
    Right j -> pure j
  where
    req = Request { reqMethod = GET
                  , reqURI = pack $ "https://logs.beuke.org/irc-logs-b0881a8.json?sql=select+*+from+db+where+" ++ (fromMisoString q)
                  , reqLogin = Nothing
                  , reqHeaders = []
                  , reqWithCredentials = False
                  , reqData = NoData
                  }



{- https://logs.beuke.org/irc-logs-b0881a8.json?sql=select+*+from+db+where+rowid+%3E+0+AND+rowid+%3C+51 -}


-- | HasURI typeclass
instance HasURI Model where
  lensURI = makeLens getter setter
    where
      getter = uri
      setter = \m u -> m { uri = u }

uriparser :: Maybe t -> t
uriparser (Just x) = x

goto :: String -> Action
goto = ChangeURI . uriparser . parseRelativeReference

goAbout :: Action
goAbout = goto "/haskell-logs/about"

goHome  :: Action
goHome = goto "/haskell-logs"

