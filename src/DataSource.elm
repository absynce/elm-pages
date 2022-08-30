module DataSource exposing
    ( DataSource
    , map, succeed, fail
    , fromResult
    , andThen, resolve, combine
    , andMap
    , map2, map3, map4, map5, map6, map7, map8, map9
    , combine2
    )

{-| In an `elm-pages` app, each page can define a value `data` which is a `DataSource` that will be resolved **before** `init` is called. That means it is also available
when the page's HTML is pre-rendered during the build step. You can also access the resolved data in `head` to use it for the page's SEO meta tags.

A `DataSource` lets you pull in data from:

  - Local files ([`DataSource.File`](DataSource-File))
  - HTTP requests ([`DataSource.Http`](DataSource-Http))
  - Globs, i.e. listing out local files based on a pattern like `content/*.txt` ([`DataSource.Glob`](DataSource-Glob))
  - Ports, i.e. getting JSON data from running custom NodeJS, similar to a port in a vanilla Elm app except run at build-time in NodeJS, rather than at run-time in the browser ([`DataSource.Port`](DataSource-Port))
  - Hardcoded data (`DataSource.succeed "Hello!"`)
  - Or any combination of the above, using `DataSource.map2`, `DataSource.andThen`, or other combining/continuing helpers from this module


## Where Does DataSource Data Come From?

Data from a `DataSource` is resolved when you load a page in the `elm-pages` dev server, or when you run `elm-pages build`.

Because `elm-pages` hydrates into a full Elm single-page app, it does need the data in order to initialize the Elm app.
So why not just get the data the old-fashioned way, with `elm/http`, for example?

A few reasons:

1.  DataSource's allow you to pull in data that you wouldn't normally be able to access from an Elm app, like local files, or listings of files in a folder. Not only that, but the dev server knows to automatically hot reload the data when the files it depends on change, so you can edit the files you used in your DataSource and see the page hot reload as you save!
2.  Because `elm-pages` has a build step, you know that your `DataSource.Http` requests succeeded, your decoders succeeded, your custom DataSource validations succeeded, and everything went smoothly. If something went wrong, you get a build failure and can deal with the issues before the site goes live. That means your users won't see those errors, and as a developer you don't need to handle those error cases in your code! Think of it as "parse, don't validate", but for your entire build.
3.  You don't have to worry about an API being down, or hitting it repeatedly. You can build in data and it will end up as JSON files served up with all the other assets of your site. If your CDN (static site host) is down, then the rest of your site is probably down anyway. If your site host is up, then so is all of your `DataSource` data. Also, it will be served up extremely quickly without needing to wait for any database queries to be performed, `andThen` requests to be resolved, etc., because all of that work and waiting was done at build-time!
4.  You can pre-render pages, including the SEO meta tags, with all that rich, well-typed Elm data available! That's something you can't accomplish with a vanilla Elm app, and it's one of the main use cases for elm-pages.


## Mental Model

You can think of a DataSource as a declarative (not imperative) definition of data. It represents where to get the data from, and how to transform it (map, combine with other DataSources, etc.).

Even though an HTTP request is non-deterministic, you should think of it that way as much as possible with a DataSource because elm-pages will only perform a given DataSource.Http request once, and
it will share the result between any other DataSource.Http requests that have the exact same URL, Method, Body, and Headers.

So calling a function to increment a counter on a server through an HTTP request would not be a good fit for a `DataSource`. Let's imagine we have an HTTP endpoint that gives these stateful results when called repeatedly:

<https://my-api.example.com/increment-counter>
-> Returns 1
<https://my-api.example.com/increment-counter>
-> Returns 2
<https://my-api.example.com/increment-counter>
-> Returns 3

If we define a `DataSource` that hits that endpoint:

    data =
        DataSource.Http.get
            "https://my-api.example.com/increment-counter"
            Decode.int

No matter how many places we use that `DataSource`, its response will be "locked in" (let's say the response was `3`, then every page would have the same value of `3` for that request).

So even though HTTP requests, JavaScript code, etc. can be non-deterministic, a `DataSource` always represents a single snapshot of a resource, and those values will be re-used as if they were a deterministic, declarative resource.
So it's best to use that mental model to avoid confusion.


## Basics

@docs DataSource

@docs map, succeed, fail

@docs fromResult


## Chaining Requests

@docs andThen, resolve, combine

@docs andMap

@docs map2, map3, map4, map5, map6, map7, map8, map9

-}

import Pages.Internal.StaticHttpBody as Body
import Pages.StaticHttp.Request as HashRequest
import Pages.StaticHttpRequest exposing (RawRequest(..))
import RequestsAndPending exposing (RequestsAndPending)


{-| A DataSource represents data that will be gathered at build time. Multiple `DataSource`s can be combined together using the `mapN` functions,
very similar to how you can manipulate values with Json Decoders in Elm.
-}
type alias DataSource error value =
    RawRequest error value


{-| Transform a request into an arbitrary value. The same underlying HTTP requests will be performed during the build
step, but mapping allows you to change the resulting values by applying functions to the results.

A common use for this is to map your data into your elm-pages view:

    import DataSource
    import Json.Decode as Decode exposing (Decoder)

    view =
        DataSource.Http.get
            (Secrets.succeed "https://api.github.com/repos/dillonkearns/elm-pages")
            (Decode.field "stargazers_count" Decode.int)
            |> DataSource.map
                (\stars ->
                    { view =
                        \model viewForPage ->
                            { title = "Current stars: " ++ String.fromInt stars
                            , body = Html.text <| "⭐️ " ++ String.fromInt stars
                            , head = []
                            }
                    }
                )

-}
map : (a -> b) -> DataSource error a -> DataSource error b
map fn requestInfo =
    case requestInfo of
        RequestError error ->
            RequestError error

        Request urls lookupFn ->
            Request
                urls
                (mapLookupFn fn lookupFn)

        ApiRoute value ->
            ApiRoute (fn value)


mapError : (errorA -> errorB) -> DataSource errorA value -> DataSource errorB value
mapError fn requestInfo =
    case requestInfo of
        RequestError error ->
            RequestError
                (case error of
                    Pages.StaticHttpRequest.UserError userError ->
                        fn userError |> Pages.StaticHttpRequest.UserError

                    Pages.StaticHttpRequest.MissingHttpResponse string requests ->
                        Pages.StaticHttpRequest.MissingHttpResponse string requests

                    Pages.StaticHttpRequest.DecoderError string ->
                        Pages.StaticHttpRequest.DecoderError string

                    Pages.StaticHttpRequest.UserCalledStaticHttpFail string ->
                        Pages.StaticHttpRequest.UserCalledStaticHttpFail string
                )

        Request urls lookupFn ->
            Request urls (\a b -> lookupFn a b |> mapError fn)

        ApiRoute value ->
            ApiRoute value


combine2 : DataSource value value -> DataSource Never value
combine2 requestInfo =
    case requestInfo of
        RequestError error ->
            liftError error

        Request urls lookupFn ->
            Request urls
                (\a b -> lookupFn a b |> combine2)

        ApiRoute value ->
            ApiRoute value


liftError : Pages.StaticHttpRequest.Error error -> RawRequest a error
liftError error =
    case error of
        Pages.StaticHttpRequest.MissingHttpResponse string requests ->
            Pages.StaticHttpRequest.MissingHttpResponse string requests
                |> RequestError

        Pages.StaticHttpRequest.DecoderError string ->
            Pages.StaticHttpRequest.DecoderError string
                |> RequestError

        Pages.StaticHttpRequest.UserCalledStaticHttpFail string ->
            Pages.StaticHttpRequest.UserCalledStaticHttpFail string
                |> RequestError

        Pages.StaticHttpRequest.UserError innerError ->
            ApiRoute innerError


mapLookupFn : (a -> b) -> (d -> c -> DataSource error a) -> d -> c -> DataSource error b
mapLookupFn fn lookupFn maybeMock requests =
    map fn (lookupFn maybeMock requests)


{-| Helper to remove an inner layer of Request wrapping.
-}
resolve : DataSource error (List (DataSource error value)) -> DataSource error (List value)
resolve =
    andThen combine


{-| Turn a list of `StaticHttp.Request`s into a single one.

    import DataSource
    import Json.Decode as Decode exposing (Decoder)

    type alias Pokemon =
        { name : String
        , sprite : String
        }

    pokemonDetailRequest : StaticHttp.Request (List Pokemon)
    pokemonDetailRequest =
        StaticHttp.get
            (Secrets.succeed "https://pokeapi.co/api/v2/pokemon/?limit=3")
            (Decode.field "results"
                (Decode.list
                    (Decode.map2 Tuple.pair
                        (Decode.field "name" Decode.string)
                        (Decode.field "url" Decode.string)
                        |> Decode.map
                            (\( name, url ) ->
                                StaticHttp.get (Secrets.succeed url)
                                    (Decode.at
                                        [ "sprites", "front_default" ]
                                        Decode.string
                                        |> Decode.map (Pokemon name)
                                    )
                            )
                    )
                )
            )
            |> StaticHttp.andThen StaticHttp.combine

-}
combine : List (DataSource error value) -> DataSource error (List value)
combine =
    List.foldr (map2 (::)) (succeed [])


{-| Like map, but it takes in two `Request`s.

    view siteMetadata page =
        StaticHttp.map2
            (\elmPagesStars elmMarkdownStars ->
                { view =
                    \model viewForPage ->
                        { title = "Repo Stargazers"
                        , body = starsView elmPagesStars elmMarkdownStars
                        }
                , head = head elmPagesStars elmMarkdownStars
                }
            )
            (get
                (Secrets.succeed "https://api.github.com/repos/dillonkearns/elm-pages")
                (Decode.field "stargazers_count" Decode.int)
            )
            (get
                (Secrets.succeed "https://api.github.com/repos/dillonkearns/elm-markdown")
                (Decode.field "stargazers_count" Decode.int)
            )

-}
map2 : (a -> b -> c) -> DataSource error a -> DataSource error b -> DataSource error c
map2 fn request1 request2 =
    case ( request1, request2 ) of
        ( RequestError error, _ ) ->
            RequestError error

        ( _, RequestError error ) ->
            RequestError error

        ( Request urls1 lookupFn1, Request urls2 lookupFn2 ) ->
            Request
                (urls1 ++ urls2)
                (mapReq fn lookupFn1 lookupFn2)

        ( Request urls1 lookupFn1, ApiRoute value2 ) ->
            Request
                urls1
                (mapReq fn lookupFn1 (\_ _ -> ApiRoute value2))

        ( ApiRoute value2, Request urls1 lookupFn1 ) ->
            Request
                urls1
                (mapReq fn (\_ _ -> ApiRoute value2) lookupFn1)

        ( ApiRoute value1, ApiRoute value2 ) ->
            ApiRoute (fn value1 value2)


mapReq : (a -> b -> c) -> (e -> d -> DataSource error a) -> (e -> d -> DataSource error b) -> e -> d -> DataSource error c
mapReq fn lookupFn1 lookupFn2 maybeMock rawResponses =
    map2 fn
        (lookupFn1 maybeMock rawResponses)
        (lookupFn2 maybeMock rawResponses)


lookup : Maybe Pages.StaticHttpRequest.MockResolver -> DataSource error value -> RequestsAndPending -> Result (Pages.StaticHttpRequest.Error error) value
lookup maybeMockResolver requestInfo rawResponses =
    case requestInfo of
        RequestError error ->
            Err error

        Request urls lookupFn ->
            lookup maybeMockResolver
                (addUrls urls (lookupFn maybeMockResolver rawResponses))
                rawResponses

        ApiRoute value ->
            Ok value


addUrls : List HashRequest.Request -> DataSource error value -> DataSource error value
addUrls urlsToAdd requestInfo =
    case requestInfo of
        RequestError error ->
            RequestError error

        Request initialUrls function ->
            Request (initialUrls ++ urlsToAdd) function

        ApiRoute value ->
            ApiRoute value


{-| The full details to perform a StaticHttp request.
-}
type alias RequestDetails =
    { url : String
    , method : String
    , headers : List ( String, String )
    , body : Body.Body
    , useCache : Bool
    }


lookupUrls : DataSource error value -> List RequestDetails
lookupUrls requestInfo =
    case requestInfo of
        RequestError _ ->
            -- TODO should this have URLs passed through?
            []

        Request urls _ ->
            urls

        ApiRoute _ ->
            []


{-| Build off of the response from a previous `DataSource` request to build a follow-up request. You can use the data
from the previous response to build up the URL, headers, etc. that you send to the subsequent request.

    import DataSource
    import Json.Decode as Decode exposing (Decoder)

    licenseData : DataSource String
    licenseData =
        DataSource.Http.get
            (Secrets.succeed "https://api.github.com/repos/dillonkearns/elm-pages")
            (Decode.at [ "license", "url" ] Decode.string)
            |> DataSource.andThen
                (\licenseUrl ->
                    DataSource.Http.get (Secrets.succeed licenseUrl) (Decode.field "description" Decode.string)
                )

-}
andThen : (a -> DataSource error b) -> DataSource error a -> DataSource error b
andThen fn requestInfo =
    Request
        (lookupUrls requestInfo)
        (\maybeMockResolver rawResponses ->
            lookup maybeMockResolver
                requestInfo
                rawResponses
                |> (\result ->
                        case result of
                            Err error ->
                                RequestError error

                            Ok value ->
                                case fn value of
                                    Request values function ->
                                        Request values function

                                    RequestError error ->
                                        RequestError error

                                    ApiRoute finalValue ->
                                        ApiRoute finalValue
                   )
        )


{-| A helper for combining `DataSource`s in pipelines.
-}
andMap : DataSource error a -> DataSource error (a -> b) -> DataSource error b
andMap =
    map2 (|>)


{-| This is useful for prototyping with some hardcoded data, or for having a view that doesn't have any StaticHttp data.

    import DataSource

    view :
        List ( PagePath, Metadata )
        ->
            { path : PagePath
            , frontmatter : Metadata
            }
        ->
            StaticHttp.Request
                { view : Model -> View -> { title : String, body : Html Msg }
                , head : List (Head.Tag Pages.PathKey)
                }
    view siteMetadata page =
        StaticHttp.succeed
            { view =
                \model viewForPage ->
                    mainView model viewForPage
            , head = head page.frontmatter
            }

-}
succeed : a -> DataSource error a
succeed value =
    ApiRoute value


{-| Stop the StaticHttp chain with the given error message. If you reach a `fail` in your request,
you will get a build error. Or in the dev server, you will see the error message in an overlay in your browser (and in
the terminal).
-}
fail : String -> DataSource error a
fail errorMessage =
    RequestError (Pages.StaticHttpRequest.UserCalledStaticHttpFail errorMessage)


{-| Turn an Err into a DataSource failure.
-}
fromResult : Result String value -> DataSource error value
fromResult result =
    case result of
        Ok okValue ->
            succeed okValue

        Err error ->
            fail error


{-| -}
map3 :
    (value1 -> value2 -> value3 -> valueCombined)
    -> DataSource error value1
    -> DataSource error value2
    -> DataSource error value3
    -> DataSource error valueCombined
map3 combineFn request1 request2 request3 =
    succeed combineFn
        |> map2 (|>) request1
        |> map2 (|>) request2
        |> map2 (|>) request3


{-| -}
map4 :
    (value1 -> value2 -> value3 -> value4 -> valueCombined)
    -> DataSource error value1
    -> DataSource error value2
    -> DataSource error value3
    -> DataSource error value4
    -> DataSource error valueCombined
map4 combineFn request1 request2 request3 request4 =
    succeed combineFn
        |> map2 (|>) request1
        |> map2 (|>) request2
        |> map2 (|>) request3
        |> map2 (|>) request4


{-| -}
map5 :
    (value1 -> value2 -> value3 -> value4 -> value5 -> valueCombined)
    -> DataSource error value1
    -> DataSource error value2
    -> DataSource error value3
    -> DataSource error value4
    -> DataSource error value5
    -> DataSource error valueCombined
map5 combineFn request1 request2 request3 request4 request5 =
    succeed combineFn
        |> map2 (|>) request1
        |> map2 (|>) request2
        |> map2 (|>) request3
        |> map2 (|>) request4
        |> map2 (|>) request5


{-| -}
map6 :
    (value1 -> value2 -> value3 -> value4 -> value5 -> value6 -> valueCombined)
    -> DataSource error value1
    -> DataSource error value2
    -> DataSource error value3
    -> DataSource error value4
    -> DataSource error value5
    -> DataSource error value6
    -> DataSource error valueCombined
map6 combineFn request1 request2 request3 request4 request5 request6 =
    succeed combineFn
        |> map2 (|>) request1
        |> map2 (|>) request2
        |> map2 (|>) request3
        |> map2 (|>) request4
        |> map2 (|>) request5
        |> map2 (|>) request6


{-| -}
map7 :
    (value1 -> value2 -> value3 -> value4 -> value5 -> value6 -> value7 -> valueCombined)
    -> DataSource error value1
    -> DataSource error value2
    -> DataSource error value3
    -> DataSource error value4
    -> DataSource error value5
    -> DataSource error value6
    -> DataSource error value7
    -> DataSource error valueCombined
map7 combineFn request1 request2 request3 request4 request5 request6 request7 =
    succeed combineFn
        |> map2 (|>) request1
        |> map2 (|>) request2
        |> map2 (|>) request3
        |> map2 (|>) request4
        |> map2 (|>) request5
        |> map2 (|>) request6
        |> map2 (|>) request7


{-| -}
map8 :
    (value1 -> value2 -> value3 -> value4 -> value5 -> value6 -> value7 -> value8 -> valueCombined)
    -> DataSource error value1
    -> DataSource error value2
    -> DataSource error value3
    -> DataSource error value4
    -> DataSource error value5
    -> DataSource error value6
    -> DataSource error value7
    -> DataSource error value8
    -> DataSource error valueCombined
map8 combineFn request1 request2 request3 request4 request5 request6 request7 request8 =
    succeed combineFn
        |> map2 (|>) request1
        |> map2 (|>) request2
        |> map2 (|>) request3
        |> map2 (|>) request4
        |> map2 (|>) request5
        |> map2 (|>) request6
        |> map2 (|>) request7
        |> map2 (|>) request8


{-| -}
map9 :
    (value1 -> value2 -> value3 -> value4 -> value5 -> value6 -> value7 -> value8 -> value9 -> valueCombined)
    -> DataSource error value1
    -> DataSource error value2
    -> DataSource error value3
    -> DataSource error value4
    -> DataSource error value5
    -> DataSource error value6
    -> DataSource error value7
    -> DataSource error value8
    -> DataSource error value9
    -> DataSource error valueCombined
map9 combineFn request1 request2 request3 request4 request5 request6 request7 request8 request9 =
    succeed combineFn
        |> map2 (|>) request1
        |> map2 (|>) request2
        |> map2 (|>) request3
        |> map2 (|>) request4
        |> map2 (|>) request5
        |> map2 (|>) request6
        |> map2 (|>) request7
        |> map2 (|>) request8
        |> map2 (|>) request9
