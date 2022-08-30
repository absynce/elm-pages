module Api exposing (routes)

import ApiRoute
import DataSource exposing (DataSource)
import Html exposing (Html)
import Pages.Manifest as Manifest
import Route exposing (Route)
import Site


routes :
    DataSource Never (List Route)
    -> (Html Never -> String)
    -> List (ApiRoute.ApiRoute ApiRoute.Response)
routes getStaticRoutes htmlToString =
    [ DataSource.succeed manifest |> Manifest.generator Site.canonicalUrl
    ]


manifest : Manifest.Config
manifest =
    Manifest.init
        { name = "Site Name"
        , description = "Description"
        , startUrl = Route.Visibility__ { visibility = Nothing } |> Route.toPath
        , icons = []
        }
