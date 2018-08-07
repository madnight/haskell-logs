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
import           Miso.String                   hiding (null, index, tail, last, splitAt, isInfixOf)
import           Prelude                       hiding (head, concat, unwords)
import           Control.Monad

import GHCJS.Types
import GHCJS.Foreign.Callback

replaceAtIndex n item ls = a ++ (item:b)
    where (a, (_:b)) = splitAt n ls

maxIndexSize = 151275

foreign import javascript unsafe "setTimeout(function(){document.getElementById($1) ? document.getElementById($1).scrollIntoView() : null;}, 500);"
   scrollIntoView :: JSString -> IO ()

-- | Model
data Model =
  Model { info  :: Maybe APIInfo
        , index :: Maybe APIInfo
        , uri   :: URI
         -- ^ current URI of application
        , query :: MisoString
        } deriving (Eq, Show)

-- | Action
data Action
  = FetchGitHub MisoString
  | SetGitHub APIInfo
  | SetQuery MisoString
  | FetchIndex MisoString
  | SetIndex APIInfo
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
           App { model = Model { info = Nothing, index = Nothing, query = "", uri = currentURI }
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

updateModel (FetchIndex s) m = m <# do
  SetIndex <$> getGitHubAPIInfo (query m)

updateModel (SetIndex apiInfo) m =
  noEff m { index = Just apiInfo }

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
  let pager = read (last $ pathSegments u) :: Integer
  let anchor = uriFragment u
  if ("index" `isInfixOf` show u) then do
   x <- SetIndex <$> getGitHubAPIInfo ((toMisoString $ "rowid+%3E+" ++ show (pager * 100)++ "+AND+rowid+%3C+" ++ show (((pager * 100) + 100))))
   if (not . null $ anchor) then do
       scrollIntoView $ toMisoString (tail anchor) 
       pure x
     else pure x
   pure x
   {- pure NoOp -}
  else
   pure NoOp

updateModel NoOp m =
  noEff m

clickGoto :: Integer -> Attribute Action
clickGoto index | index < 0 = onClick NoOp
                | index > maxIndexSize = onClick NoOp
                | otherwise = onClick $ goto $ "/haskell-logs/index/" ++ show index

clickGoto' :: String -> Attribute Action
clickGoto' str = onClick $ goto $ "/haskell-logs/index/" ++ str


pagLink :: Integer -> View Action
pagLink index | index < 0 = div_ [] []
              | index > maxIndexSize = div_ [] []
              | otherwise =  li_ [clickGoto index]
                    [a_ [class_ $ pack "pagination-link"
                       , textProp "aria-label" $ pack ""
                       ] [text . pack $ show index]]


pagLinkLeft index p | index < 3 = div_ [] []
                    | otherwise = pagLink p

pagLinkRight index p | index > (maxIndexSize-3) = div_ [] []
                     | otherwise = pagLink p


pagDotsLeft index | index < 3 = div_ [] []
                  | otherwise = li_ [] [span_ [class_ $ pack "pagination-ellipsis" ] [text $ pack "..."]]

pagDotsRight index | index > maxIndexSize-3 = div_ [] []
                   | otherwise = li_ [] [span_ [class_ $ pack "pagination-ellipsis" ] [text $ pack "..."]]

pagCurrent :: Integer -> View Action
pagCurrent index = i_ [] [a_ [class_ $ pack "pagination-link is-current", textProp "aria-label" $ pack "", textProp "aria-current" $ pack "page"] [text . pack $ show index]]


pagPrevNext True index a b = a_  [class_ $ pack a , clickGoto index, disabled_ True] [text b]
pagPrevNext False index a b = a_  [class_ $ pack a , clickGoto index] [text b]

pagPrev index = pagPrevNext (index < 0) index "pagination-previous" "Previous"
pagNext index = pagPrevNext (index > maxIndexSize) index "pagination-next" "Next Page"


-- | View function, with routing
viewModel :: Model -> View Action
viewModel model@Model {..}
    | "index" `isInfixOf` show uri = about
    | otherwise = view
  where

    url = uriparser . parseURI
    pager = read (last $ pathSegments uri) :: Integer

    onLoaded action = on "onload" emptyDecoder $ \() -> action

    about = div_ [ style_ $ M.fromList [
                  (pack "text-align", pack "center")
                , (pack "margin", pack "50px")
                ]
               ] [

        h1_ [class_ $ pack "title"] [ text $ pack "Haskell IRC Log Index" ]
        , nav_ [class_ $ pack "pagination"
              , textProp "role" $ pack "navigation"
              , textProp "aria-label" $ pack "pagination"
              ] [

            pagPrev $ pager - 1
          , pagNext $ pager + 1
          , ul_  [class_ $ pack "pagination-list"]
          [
            pagLinkLeft     pager 0
          , pagDotsLeft     pager
          , pagLink       $ pager - 2
          , pagLink       $ pager - 1
          , pagCurrent    $ pager + 0
          , pagLink       $ pager + 1
          , pagLink       $ pager + 2
          , pagDotsRight    pager
          , pagLinkRight    pager maxIndexSize
          ]
          ]
        ,
           case index of
          Nothing -> div_ [] [ text $ pack "Loading ...." ]
          Just APIInfo{..} ->
            div_ [] [
               br_ [] []
               , th_ [] [ text
               $ pack ("Log Entries [" ++ show (pager * 100)  ++ ".." ++ (show ((pager * 100) + 100)) ++ "] ")]
               , th_ [] [ text $ ""]
               , table_ [ class_ $ pack "table is-striped" ] [
                 thead_ [] [td_ [] [i] | i <- ["Date", "Time", "User", "Post"]]
               , tbody_ [onLoaded $ HandleURI uri ] $ results_ rows
                 ]
               ]
            ]

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

      , input_ attrs [ text $ pack "" ]

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
                , onInput (\x -> SetQuery $ toMisoString $ "post+like+%22%25" ++ (fromMisoString x :: String) ++ "%25%22+limit+14")
                , autofocus_ True
                , class_ $ pack "button is-large is-outlined"
                ] ++ [ disabled_ False | isJust info ]


pattern EnterButton :: KeyCode
pattern EnterButton = KeyCode 13

pager :: MisoString -> String
pager x = show ((read (fromMisoString x) :: Integer) `div` 100) ++ "#" ++ (fromMisoString x)

results_ :: [[MisoString]] -> [View Action]
results_ ((a:b:c:d:e):xs) = tr_ [id_ (fromMisoString a), clickGoto' $ pager a] (tdd $ fromatRow (a:b:c:d:e)) : results_ xs
{- results_ ((a:b:c:d:e):xs) = tr_ [clickGoto 50] (tdd $ fromatRow (a:b:c:d:e)) : results_ xs -}
results_ _ = []

fromatRow :: [MisoString] -> [MisoString]
fromatRow (a:b:c:d:e) = b : c : concat ["<", d, ">"] : e

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
                  , reqURI = pack $ "https://logs.beuke.org/irc-logs-b0881a8.json?sql=select+cast%28rowid+as+text%29%2C+*+from+db+where+" ++ (fromMisoString q)
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
goAbout = goto "/haskell-logs/index"

goHome  :: Action
goHome = goto "/haskell-logs"

