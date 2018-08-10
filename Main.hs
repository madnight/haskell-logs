{-# LANGUAGE DataKinds                 #-}
{-# LANGUAGE DeriveGeneric             #-}
{-# LANGUAGE GADTs                     #-}
{-# LANGUAGE LambdaCase                #-}
{-# LANGUAGE NoMonomorphismRestriction #-}
{-# LANGUAGE OverloadedStrings         #-}
{-# LANGUAGE PatternSynonyms           #-}
{-# LANGUAGE RecordWildCards           #-}
{-# LANGUAGE ScopedTypeVariables       #-}
{-# LANGUAGE TypeFamilies              #-}
{-# LANGUAGE TypeOperators             #-}

module Main where

import           Control.Monad                 (unless)
import           Data.Aeson                    (eitherDecodeStrict)
import           Data.Aeson.Types
import           Data.List                     (intercalate, isInfixOf)
import           Data.Map                      (fromList)
import           Data.Maybe                    (isJust)
import           GHC.Generics
import           GHCJS.Types                   (JSString)
import           JavaScript.Web.XMLHttpRequest
import           Miso                          hiding (defaultOptions)
import qualified Miso.String                   as M
import           Network.URI                   hiding (query)

foreign import javascript safe
    " setTimeout(                             \
    \   function() {                          \
    \    var e = document.getElementById($1); \
    \    if (e) e.scrollIntoView();           \
    \   }, 500);                              "
   scrollIntoView :: JSString -> IO ()

-- | Model
data Model =
  Model { searchResult  :: Maybe APIResult
        , index         :: Maybe APIResult
        , uri           :: URI
         -- ^ current URI of application
        , query         :: M.MisoString
        } deriving (Eq, Show)

-- | Action
data Action where
    QueryAPI       :: Action
    SetAPIResponse :: APIResult    -> Action
    SetQuery       :: M.MisoString -> Action
    SetIndex       :: APIResult    -> Action
    HandleURI      :: URI          -> Action
    ChangeURI      :: URI          -> Action
    NoOp           :: Action
  deriving (Show, Eq)

data APIResult = APIResult
  { database :: M.MisoString
  , rows     :: [[M.MisoString]]
  , query_ms :: Float
  } deriving (Show, Eq, Generic)

instance FromJSON APIResult where
  parseJSON = genericParseJSON
    defaultOptions { fieldLabelModifier = camelTo '_' }

-- | Main entry point
main :: IO ()
main = do
   currentURI <- getCurrentURI
   startApp App { model =
                    Model { searchResult = Nothing
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


maxIndexSize :: Integer
maxIndexSize = 151275

fMS :: M.ToMisoString str => M.MisoString -> str
fMS = M.fromMisoString

pattern EnterButton :: KeyCode
pattern EnterButton = KeyCode 13

-- | Update your model
updateModel :: Action -> Model -> Effect Action Model

updateModel (SetIndex apiInfo) m =
  noEff m { index = Just apiInfo }

updateModel QueryAPI m = m <# do
  SetAPIResponse <$> queryLogDatabase (query m)

updateModel (SetQuery q) m =
  noEff m { query = q }

updateModel (SetAPIResponse apiInfo) m =
  noEff m { searchResult = Just apiInfo }

updateModel (ChangeURI u) m = m <# do
  pushURI u
  pure NoOp

updateModel (HandleURI u) m = m { uri = u } <# do
  let pager = read (last $ pathSegments u) :: Integer
  let anchor = uriFragment u
  let query = M.toMisoString $ intercalate "+"
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

pgLink :: Integer -> View Action
pgLink i
  | i < 0 || i > maxIndexSize = emptyDiv
  | otherwise = li_
    [clickGoto i]
    [ a_
        [class_ $ M.pack "pagination-link", textProp "aria-label" $ M.pack ""]
        [text . M.pack $ show i]
    ]

dots :: View action
dots = li_ [] [span_
              [class_ $ M.pack "pagination-ellipsis" ]
              [text $ M.pack "..."]]

pgCurrent :: Integer -> View Action
pgCurrent i = i_ []
  [ a_
      [ class_ $ M.pack "pagination-link is-current"
      , textProp "aria-label" $ M.pack ""
      , textProp "aria-current" $ M.pack "page"
      ]
      [text . M.pack $ show i]
  ]

pgPrevNext :: String -> M.MisoString -> Integer -> Bool -> View Action
pgPrevNext a b i True =
  a_ [class_ $ M.pack a, clickGoto i, disabled_ True] [text b]
pgPrevNext a b i False = a_ [class_ $ M.pack a, clickGoto i] [text b]

notFound404 :: View Action
notFound404 =
  div_ [] [text "the 404 :(", button_ [onClick $ goto "/haskell-logs"]
  [text "go home Y"]]

headerStyle :: Attribute action
headerStyle = style_ $ fromList [
      (M.pack "text-align", M.pack "center")
    , (M.pack "margin", M.pack "50px")]

header :: String -> View action
header s = h1_ [class_ $ M.pack "title"] [text $ M.pack s]

pagination :: Model -> View Action
pagination model@Model {..} =
  let pager = read (last $ pathSegments uri) :: Integer
      pgNext = pgPrevNext "pagination-next" "Next Page" <*> (> maxIndexSize)
      pgPrev = pgPrevNext "pagination-previous" "Previous" <*> (< 0)
      b ==> f = if b then f else emptyDiv
      pgDotsRight i   = (i <= maxIndexSize - 3) ==> dots
      pgLinkRight i p = (i <= maxIndexSize - 3) ==> pgLink p
      pgDotsLeft  i   = (i >=                3) ==> dots
      pgLinkLeft  i p = (i >=                3) ==> pgLink p
  in
    nav_
        [ class_ $ M.pack "pagination"
        , textProp "role" $ M.pack "navigation"
        , textProp "aria-label" $ M.pack "pagination"
        ]
        [ pgPrev $ pager - 1
        , pgNext $ pager + 1
        , ul_
          [class_ $ M.pack "pagination-list"]
          [ pgLinkLeft pager 0
          , pgDotsLeft pager
          , pgLink $ pager - 2
          , pgLink $ pager - 1
          , pgCurrent $ pager + 0
          , pgLink $ pager + 1
          , pgLink $ pager + 2
          , pgDotsRight pager
          , pgLinkRight pager maxIndexSize
          ]
        ]

indexView :: Model -> View Action
indexView model@Model {..} =
  let pager = read (last $ pathSegments uri) :: Integer
      onLoaded = on "onload" emptyDecoder . const
  in
    div_
      [ headerStyle ]
      [ header "Haskell IRC Log Index"
      , pagination model
      , case index of
        Nothing             -> div_ [] [text $ M.pack "Loading ...."]
        Just APIResult {..} -> div_ [] [ br_ [] [] , th_ []
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
            [ thead_ [] [ td_ [] [i] | i <- ["Date", "Time", "User", "Post"]]
            , tbody_ [onLoaded $ HandleURI uri] $ results_ rows
            ]
          ]
      ]

searchInput :: Model -> View Action
searchInput model@Model {..} = input_ ([ onKeyDown $ \case
         EnterButton -> QueryAPI
         _           -> NoOp
       , onInput (\x -> SetQuery $ M.toMisoString $ intercalate "+"
           [ "post"
           , "like"
           , "\"%"
           , fMS x :: String
           , "%\""
           , "limit"
           , "14"
           ]
         )
       , autofocus_ True
       , class_ $ M.pack "button is-large is-outlined"
       ] ++ [ disabled_ False | isJust searchResult ])
       [text $ M.pack ""]

searchView :: Model -> View Action
searchView model@Model {..} =
  div_
    [ headerStyle ]
    [ header "Haskell IRC Log Search"
  , searchInput model
  , case searchResult of
    Nothing             -> div_ [] [text $ M.pack ""]
    Just APIResult {..} -> div_ [] [ br_ [] [] , th_ []
        [text $ M.pack ("Search Results (" ++ show (round query_ms) ++ " ms)")]
      , table_
        [class_ $ M.pack "table is-striped"]
        [ thead_ [] [ td_ [] [i] | i <- ["Date", "Time", "User", "Post"] ]
        , tbody_ [] $ results_ rows
        ]
      ]
  ]

viewModel :: Model -> View Action
viewModel model@Model {..}
    | "index" `isInfixOf` show uri = indexView model
    | otherwise = searchView model

results_ :: [[M.MisoString]] -> [View Action]
results_ ((a:b:c:d:e):xs) =
 let formatRow (a:b:c:d:e) = b:c: M.concat ["<", d, ">"] :e
 in tr_ [id_ (fMS a), clickGoto' $ pager a]
      (tdd $ formatRow (a:b:c:d:e))
    : results_ xs
 where
   pager s = show ((read (fMS s) :: Integer) `div` 100) ++ "#" ++ fMS s
   tdd (x:xs) = td_ [] [text x] : tdd xs
   tdd _      = []
results_ _ = []

parseURI :: String -> URI
parseURI =  uriparser . parseRelativeReference
 where
   uriparser (Just x) = x
   uriparser Nothing = error "404"

goto :: String -> Action
goto = ChangeURI . uriparser . parseRelativeReference
 where
   uriparser (Just x) = x
   uriparser Nothing = error "404"

queryLogDatabase :: M.MisoString -> IO APIResult
queryLogDatabase q = do
  Just resp <- contents <$> xhrByteString req
  case eitherDecodeStrict resp :: Either String APIResult of
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
      , fMS q
      ]
    , reqLogin           = Nothing
    , reqHeaders         = []
    , reqWithCredentials = False
    , reqData            = NoData
    }
