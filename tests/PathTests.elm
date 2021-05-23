module PathTests exposing (all)

import Expect
import Path
import Test exposing (describe, test)


all =
    describe "Path"
        [ test "join two segments" <|
            \() ->
                Path.join [ "a", "b", "c" ]
                    |> Path.toAbsolute
                    |> Expect.equal "/a/b/c"
        , test "join segments that have paths in them" <|
            \() ->
                Path.join [ "a", "b", "c/d/e" ]
                    |> Path.toAbsolute
                    |> Expect.equal "/a/b/c/d/e"
        , test "removes trailing and leading slashes" <|
            \() ->
                Path.join [ "a/", "/b/", "/c/d/e/" ]
                    |> Path.toAbsolute
                    |> Expect.equal "/a/b/c/d/e"
        ]
