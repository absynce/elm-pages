module Pages.Form exposing (..)

import Dict exposing (Dict)
import Html exposing (Attribute)
import Html.Attributes
import Html.Events
import Json.Decode as Decode exposing (Decoder)
import Pages.Msg


listeners : String -> List (Attribute (Pages.Msg.Msg userMsg))
listeners formId =
    [ Html.Events.on "focusin" (Decode.value |> Decode.map Pages.Msg.FormFieldEvent)
    , Html.Events.on "focusout" (Decode.value |> Decode.map Pages.Msg.FormFieldEvent)
    , Html.Events.on "input" (Decode.value |> Decode.map Pages.Msg.FormFieldEvent)
    , Html.Attributes.id formId
    ]


type Event
    = InputEvent String
    | FocusEvent
      --| ChangeEvent
    | BlurEvent


type alias FieldEvent =
    { value : String
    , formId : String
    , name : String
    , event : Event
    }


fieldEventDecoder : Decoder FieldEvent
fieldEventDecoder =
    Decode.map4 FieldEvent
        (Decode.at [ "target", "value" ] Decode.string)
        (Decode.at [ "currentTarget", "id" ] Decode.string)
        (Decode.at [ "target", "name" ] Decode.string)
        fieldDecoder


fieldDecoder : Decoder Event
fieldDecoder =
    Decode.field "type" Decode.string
        |> Decode.andThen
            (\type_ ->
                case type_ of
                    "input" ->
                        Decode.at [ "target", "type" ] Decode.string
                            |> Decode.andThen
                                (\targetType ->
                                    case targetType of
                                        "checkbox" ->
                                            Decode.map2
                                                (\valueWhenChecked isChecked ->
                                                    (if isChecked then
                                                        valueWhenChecked

                                                     else
                                                        ""
                                                    )
                                                        |> InputEvent
                                                )
                                                (Decode.at [ "target", "value" ] Decode.string)
                                                (Decode.at [ "target", "checked" ] Decode.bool)

                                        _ ->
                                            Decode.map
                                                InputEvent
                                                (Decode.at [ "target", "value" ] Decode.string)
                                )

                    "focusin" ->
                        FocusEvent
                            |> Decode.succeed

                    "focusout" ->
                        BlurEvent
                            |> Decode.succeed

                    _ ->
                        Decode.fail "Unexpected event.type"
            )


update : Decode.Value -> PageFormState -> PageFormState
update eventObject pageFormState =
    --if Dict.isEmpty pageFormState then
    --    -- TODO get all initial field values
    --    pageFormState
    --
    --else
    case eventObject |> Decode.decodeValue fieldEventDecoder |> Debug.log "fieldEvent" of
        Ok fieldEvent ->
            pageFormState
                |> Dict.update fieldEvent.formId
                    (\previousValue_ ->
                        let
                            previousValue : FormState
                            previousValue =
                                previousValue_
                                    |> Maybe.withDefault init
                        in
                        previousValue
                            |> updateForm fieldEvent
                            |> Just
                    )

        Err _ ->
            pageFormState


setField : { formId : String, name : String, value : String } -> PageFormState -> PageFormState
setField info pageFormState =
    pageFormState
        |> Dict.update info.formId
            (\previousValue_ ->
                let
                    previousValue : FormState
                    previousValue =
                        previousValue_
                            |> Maybe.withDefault init
                in
                { previousValue
                    | fields =
                        previousValue.fields
                            |> Dict.update info.name
                                (\previousFieldValue_ ->
                                    let
                                        previousFieldValue : FieldState
                                        previousFieldValue =
                                            previousFieldValue_
                                                |> Maybe.withDefault { value = "", status = NotVisited }
                                    in
                                    { previousFieldValue | value = info.value }
                                        |> Just
                                )
                }
                    |> Just
            )


updateForm : FieldEvent -> FormState -> FormState
updateForm fieldEvent formState =
    { formState
        | fields =
            formState.fields
                |> Dict.update fieldEvent.name
                    (\previousValue_ ->
                        let
                            previousValue : FieldState
                            previousValue =
                                previousValue_
                                    |> Maybe.withDefault { value = fieldEvent.value, status = NotVisited }
                        in
                        (case fieldEvent.event of
                            InputEvent newValue ->
                                { previousValue | value = newValue }

                            FocusEvent ->
                                { previousValue | status = previousValue.status |> increaseStatusTo Focused }

                            BlurEvent ->
                                { previousValue | status = previousValue.status |> increaseStatusTo Blurred }
                        )
                            |> Just
                    )
    }


setSubmitAttempted : String -> PageFormState -> PageFormState
setSubmitAttempted fieldId pageFormState =
    pageFormState
        |> Dict.update fieldId
            (\maybeForm ->
                case maybeForm of
                    Just formState ->
                        Just { formState | submitAttempted = True }

                    Nothing ->
                        Just { init | submitAttempted = True }
            )


init : FormState
init =
    { fields = Dict.empty
    , submitAttempted = False
    }


type alias PageFormState =
    Dict String FormState


type alias FormState =
    { fields : Dict String FieldState
    , submitAttempted : Bool
    }


type alias FieldState =
    { value : String
    , status : FieldStatus
    }


type FieldStatus
    = NotVisited
    | Focused
    | Changed
    | Blurred


increaseStatusTo : FieldStatus -> FieldStatus -> FieldStatus
increaseStatusTo increaseTo currentStatus =
    if statusRank increaseTo > statusRank currentStatus then
        increaseTo

    else
        currentStatus


statusRank : FieldStatus -> Int
statusRank status =
    case status of
        NotVisited ->
            0

        Focused ->
            1

        Changed ->
            2

        Blurred ->
            3
