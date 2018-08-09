{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE DeriveGeneric       #-}
{-# LANGUAGE LambdaCase          #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE PatternSynonyms     #-}
{-# LANGUAGE RecordWildCards     #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeFamilies        #-}
{-# LANGUAGE TypeOperators       #-}

module Main where

import           Control.Monad
import           Data.Aeson
import           Data.Aeson.Types
import           Data.List                     (intercalate, isInfixOf)
import           Data.Map                      (fromList)
import           Data.Maybe
import           Data.Proxy
import           GHC.Generics
import           GHCJS.Foreign.Callback
import           GHCJS.Types
import           JavaScript.Web.XMLHttpRequest
import           Miso                          hiding (defaultOptions)
import qualified Miso.String                   as M
import           Network.URI                   hiding (query)
import           Servant.API                   hiding (GET)
import           Servant.Utils.Links

maxIndexSize :: Integer
maxIndexSize = 151275

foreign import javascript safe
    " setTimeout(                             \
    \   function() {                          \
    \    var e = document.getElementById($1); \
    \    if (e) e.scrollIntoView();           \
    \   }, 500);"
   scrollIntoView :: JSString -> IO ()

-- | Model
data Model =
  Model { info  :: Maybe APIInfo
        , index :: Maybe APIInfo
        , uri   :: URI
         -- ^ current URI of application
        , query :: M.MisoString
        } deriving (Eq, Show)

-- | Action
data Action =
    FetchGitHub M.MisoString
  | SetGitHub APIInfo
  | SetQuery M.MisoString
  | FetchIndex M.MisoString
  | SetIndex APIInfo
  | HandleURI URI
  | ChangeURI URI
  | NoOp
  deriving (Show, Eq)

-- | Main entry point
main :: IO ()
main = do
   currentURI <- getCurrentURI
   startApp App { model = Model { info = Nothing
                                , index = Nothing
                                , query = ""
                                , uri = currentURI
                                }
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
  SetIndex <$> queryLogDatabase (query m)

updateModel (SetIndex apiInfo) m =
  noEff m { index = Just apiInfo }

updateModel (FetchGitHub s) m = m <# do
  SetGitHub <$> queryLogDatabase (query m)

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
  let query = M.toMisoString $
          intercalate "+"
          ["rowid", ">"
          , show (pager * 100)
          , "AND"
          , "rowid"
          , "<"
          , show (pager * 100 + 100)
          ]
  if "index" `isInfixOf` show u then do
      result <- SetIndex <$> queryLogDatabase query
      unless (null anchor) (scrollIntoView $ M.toMisoString (tail anchor))
      pure result
  else
      pure NoOp

updateModel NoOp m =
  noEff m

clickGoto :: Integer -> Attribute Action
clickGoto i | i < 0 = onClick NoOp
            | i > maxIndexSize = onClick NoOp
            | otherwise = onClick . goto $ "/haskell-logs/index/" ++ show i

clickGoto' :: String -> Attribute Action
clickGoto' str = onClick $ goto $ "/haskell-logs/index/" ++ str

emptyDiv :: View action
emptyDiv = div_ [] []

pagLink :: Integer -> View Action
pagLink i
  | i < 0 || i > maxIndexSize = emptyDiv
  | otherwise = li_
    [clickGoto i]
    [ a_
        [class_ $ M.pack "pagination-link", textProp "aria-label" $ M.pack ""]
        [text . M.pack $ show i]
    ]

pagLinkLeft :: Integer -> Integer -> View Action
pagLinkLeft i p | i < 3     = emptyDiv
                | otherwise = pagLink p

pagLinkRight :: Integer -> Integer -> View Action
pagLinkRight i p | i > (maxIndexSize - 3) = emptyDiv
                 | otherwise              = pagLink p

dots :: View action
dots = li_ [] [span_
              [class_ $ M.pack "pagination-ellipsis" ]
              [text $ M.pack "..."]]

pagDotsLeft :: Integer -> View Action
pagDotsLeft i = if i < 3 then emptyDiv else dots

pagDotsRight :: Integer -> View Action
pagDotsRight i = if i > maxIndexSize - 3 then emptyDiv else dots

pagCurrent :: Integer -> View Action
pagCurrent i = i_
  []
  [ a_
      [ class_ $ M.pack "pagination-link is-current"
      , textProp "aria-label" $ M.pack ""
      , textProp "aria-current" $ M.pack "page"
      ]
      [text . M.pack $ show i]
  ]

pagPrevNext :: Bool -> Integer -> String -> M.MisoString -> View Action
pagPrevNext True i a b =
  a_ [class_ $ M.pack a, clickGoto i, disabled_ True] [text b]
pagPrevNext False i a b = a_ [class_ $ M.pack a, clickGoto i] [text b]

pagPrev :: Integer -> View Action
pagPrev index = pagPrevNext (index < 0) index "pagination-previous" "Previous"

pagNext :: Integer -> View Action
pagNext index =
   pagPrevNext (index > maxIndexSize) index "pagination-next" "Next Page"

notFound404 :: View Action
notFound404 =
  div_ [] [text "the 404 :(", button_ [onClick goHome] [text "go home Y"]]

onLoaded :: action -> Attribute action
onLoaded action = on "onload" emptyDecoder $ \() -> action

headerStyle :: Attribute action
headerStyle = style_ $ fromList [
                  (M.pack "text-align", M.pack "center")
                , (M.pack "margin", M.pack "50px")
                ]

header :: String -> View action
header s = h1_ [class_ $ M.pack "title"] [text $ M.pack s]

indexView :: Model -> View Action
indexView model@Model {..} =
  let pager = read (last $ pathSegments uri) :: Integer
  in
    div_
      [ headerStyle ]
      [ header "Haskell IRC Log Index"
      , nav_
        [ class_ $ M.pack "pagination"
        , textProp "role" $ M.pack "navigation"
        , textProp "aria-label" $ M.pack "pagination"
        ]
        [ pagPrev $ pager - 1
        , pagNext $ pager + 1
        , ul_
          [class_ $ M.pack "pagination-list"]
          [ pagLinkLeft pager 0
          , pagDotsLeft pager
          , pagLink $ pager - 2
          , pagLink $ pager - 1
          , pagCurrent $ pager + 0
          , pagLink $ pager + 1
          , pagLink $ pager + 2
          , pagDotsRight pager
          , pagLinkRight pager maxIndexSize
          ]
        ]
      , case index of
        Nothing           -> div_ [] [text $ M.pack "Loading ...."]
        Just APIInfo {..} -> div_
          []
          [ br_ [] []
          , th_
            []
            [ text $ M.pack
                (  "Log Entries ["
                ++ show (pager * 100)
                ++ ".."
                ++ show ((pager * 100) + 100)
                ++ "] "
                )
            ]
          , th_ [] []
          , table_
            [class_ $ M.pack "table is-striped"]
            [ thead_ [] [ td_ [] [i] | i <- ["Date", "Time", "User", "Post"] ]
            , tbody_ [onLoaded $ HandleURI uri] $ results_ rows
            ]
          ]
      ]


searchView :: Model -> View Action
searchView model@Model {..} =
  div_
    [ headerStyle ]
    [ header "Haskell IRC Log Search"
  , input_ attrs [text $ M.pack ""]
  , case info of
    Nothing           -> div_ [] [text $ M.pack ""]
    Just APIInfo {..} -> div_
      []
      [ br_ [] []
      , th_
        []
        [text $ M.pack ("Search Results (" ++ show (round query_ms) ++ " ms)")]
      , table_
        [class_ $ M.pack "table is-striped"]
        [ thead_ [] [ td_ [] [i] | i <- ["Date", "Time", "User", "Post"] ]
        , tbody_ [] $ results_ rows
        ]
      ]
  ]
 where
   attrs =
     [ onKeyDown $ \case
         EnterButton -> FetchGitHub "  "
         _           -> NoOp
       , onInput
         (\x -> SetQuery $ M.toMisoString $ intercalate
           "+"
           [ "post"
           , "like"
           , "\"%"
           , M.fromMisoString x :: String
           , "%\""
           , "limit"
           , "14"
           ]
         )
       , autofocus_ True
       , class_ $ M.pack "button is-large is-outlined"
       ]
       ++ [ disabled_ False | isJust info ]

viewModel :: Model -> View Action
viewModel model@Model {..}
    | "index" `isInfixOf` show uri = indexView model
    | otherwise = searchView model

pattern EnterButton :: KeyCode
pattern EnterButton = KeyCode 13

pager :: M.MisoString -> String
pager s =
  show ((read (M.fromMisoString s) :: Integer) `div` 100)
    ++ "#"
    ++ M.fromMisoString s

results_ :: [[M.MisoString]] -> [View Action]
results_ ((a:b:c:d:e):xs) =
  tr_ [id_ (M.fromMisoString a), clickGoto' $ pager a]
      (tdd $ fromatRow (a:b:c:d:e))
    : results_ xs
results_ _ = []

fromatRow :: [M.MisoString] -> [M.MisoString]
fromatRow (a:b:c:d:e) = b:c: M.concat ["<", d, ">"] :e

tdd :: [M.MisoString] -> [View action]
tdd (x:xs) = td_ [] [text x] : tdd xs
tdd _      = []

data APIInfo = APIInfo
  { database :: M.MisoString
  , rows     :: [[M.MisoString]]
  , query_ms :: Float
  } deriving (Show, Eq, Generic)

instance FromJSON APIInfo where
  parseJSON = genericParseJSON
    defaultOptions { fieldLabelModifier = camelTo '_' }

queryLogDatabase :: M.MisoString -> IO APIInfo
queryLogDatabase q = do
  Just resp <- contents <$> xhrByteString req
  case eitherDecodeStrict resp :: Either String APIInfo of
    Left  s -> error s
    Right j -> pure j
 where
  baseUrl = "https://logs.beuke.org/"
  dataset = "irc-logs-b0881a8.json?sql="
  req     = Request
    { reqMethod          = GET
    , reqURI             = M.pack $ baseUrl ++ dataset ++ intercalate
      "+"
      [ "select"
      , "cast(rowid"
      , "as"
      , "text),"
      , "*"
      , "from"
      , "db"
      , "where"
      , M.fromMisoString q
      ]
    , reqLogin           = Nothing
    , reqHeaders         = []
    , reqWithCredentials = False
    , reqData            = NoData
    }


-- | HasURI typeclass
instance HasURI Model where
  lensURI = makeLens getter setter
    where
      getter = uri
      setter m u = m { uri = u }

uriparser :: Maybe t -> t
uriparser (Just x) = x

goto :: String -> Action
goto = ChangeURI . uriparser . parseRelativeReference

goAbout :: Action
goAbout = goto "/haskell-logs/index"

goHome  :: Action
goHome = goto "/haskell-logs"

