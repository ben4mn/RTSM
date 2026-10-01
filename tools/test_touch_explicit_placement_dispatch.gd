extends Node
## Actual Input.parse_input_event dispatch and its synthesized mouse events.
var _failures: Array[String] = []

func _ready() -> void:
    call_deferred("_run")

func _run() -> void:
    AudioManager.set_all_enabled(false)
    get_window().size=Vector2i(844,390)
    get_window().content_scale_factor=1.0
    Input.emulate_mouse_from_touch=true
    GameManager.guided_opening_enabled=false
    GameManager.selected_population_limit=30
    GameManager.selected_map_seed=101
    var main: Node=load("res://scenes/main/main.tscn").instantiate()
    add_child(main)
    for frame: int in 900:
        if main.get("_building_placement")!=null and GameManager.current_state==GameManager.GameState.PLAYING:
            break
        await get_tree().process_frame
    var hud: CanvasLayer=main.get_node("HUD")
    var map: Node2D=main.get_node("GameMap")
    var placement: Node=main.get("_building_placement")
    var palette: Node=main.get("_build_menu")
    var wood_before: int=ResourceManager.get_all_resources(0).get("wood",0)
    var buildings_before: int=main.get("_player_buildings")[0].size()
    var age_before: int=GameManager.get_player_age(0)
    await _tap((hud.get("_town_center_button") as Button).get_global_rect().get_center())
    await _tap((hud.get("age_up_button") as Button).get_global_rect().get_center())
    _expect(GameManager.get_player_age(0)==age_before,"Age Up advanced despite insufficient starting resources")
    var rejection: Label=null
    for toast: Control in (hud.get("_notification_container") as Control).get_children():
        if not toast.is_queued_for_deletion() and toast.visible and (toast.get_child(0) as Label).text.begins_with("Need +"):
            rejection=toast.get_child(0)
    _expect(rejection!=null,"actual Age Up touch did not produce resource rejection feedback")
    if rejection:
        _expect(rejection.size.y>=rejection.get_theme_font("font").get_height(rejection.get_theme_font_size("font_size")),"actual Age Up rejection text collapsed")
        _expect(rejection.get_line_count()==rejection.get_visible_line_count(),"actual Age Up rejection hides resource costs")
        print("Age Up rejection: ",rejection.text," label_rect=",rejection.get_global_rect()," lines=",rejection.get_line_count()," visible_lines=",rejection.get_visible_line_count())
    await _tap((hud.get("_selection_back_button") as Button).get_global_rect().get_center())
    await _tap((hud.get("build_menu_button") as Button).get_global_rect().get_center())
    _expect(bool(palette.get("visible")),"real touch did not open Build")
    var house_card: Button=palette.get("_button_map")[BuildingData.BuildingType.HOUSE]
    await _tap(house_card.get_global_rect().get_center())
    _expect(bool(placement.get("active")),"real House-card touch did not enter preview")
    _expect(int(ResourceManager.get_all_resources(0).get("wood",0))==wood_before,"House-card touch spent before Place")
    var preview_world: Vector2=placement.get("global_position")
    var preview_screen: Vector2=get_viewport().get_canvas_transform()*preview_world
    # The bridge sends the same screen touch down/up pair; mouse synthesis is
    # allowed to run naturally before either unhandled touch callback.
    await _tap(preview_screen)
    _expect(bool(placement.get("active")),"world preview tap committed placement")
    _expect(int(ResourceManager.get_all_resources(0).get("wood",0))==wood_before,"world touch spent wood without explicit Place")
    _expect(main.get("_player_buildings")[0].size()==buildings_before,"world touch created a foundation without Place")
    var valid_world: Vector2=placement.call("_find_initial_preview_position",preview_world)
    placement.call("update_preview_at_world",valid_world)
    await get_tree().process_frame
    await get_tree().process_frame
    var place_button: Button=hud.get("_placement_confirm_button")
    _expect(not place_button.disabled,"initial legal preview did not enable Place")
    await _tap(place_button.get_global_rect().get_center())
    var house_cost: int=BuildingData.get_building_cost(BuildingData.BuildingType.HOUSE).get("wood",0)
    _expect(int(ResourceManager.get_all_resources(0).get("wood",0))==wood_before-house_cost,"explicit Place did not spend once")
    _expect(main.get("_player_buildings")[0].size()==buildings_before+1,"explicit Place did not create one foundation")
    # A real desktop mouse remains a supported direct placement mechanism.
    main.call("_on_building_selected_for_placement",BuildingData.BuildingType.HOUSE)
    placement.set("_last_touch_input_msec",-10000)
    valid_world=placement.call("_find_initial_preview_position",valid_world+Vector2(96,48))
    var mouse:=InputEventMouseButton.new()
    mouse.device=0
    mouse.position=get_viewport().get_canvas_transform()*valid_world
    mouse.global_position=mouse.position
    mouse.button_index=MOUSE_BUTTON_LEFT
    mouse.pressed=true
    Input.parse_input_event(mouse)
    await get_tree().process_frame
    _expect(main.get("_player_buildings")[0].size()==buildings_before+2,"physical mouse placement was disabled")
    main.free()
    for failure: String in _failures:
        push_error("[FAIL] touch_explicit_placement_dispatch: "+failure)
    if _failures.is_empty():
        print("[PASS] touch_explicit_placement_dispatch: actual Age Up rejection is readable; touch/card/world dispatch spends zero before Place; explicit Place spends once; physical mouse still places")
    get_tree().quit(0 if _failures.is_empty() else 1)

func _tap(position: Vector2) -> void:
    for pressed: bool in [true,false]:
        var event:=InputEventScreenTouch.new()
        event.position=position
        event.index=0
        event.pressed=pressed
        Input.parse_input_event(event)
        await get_tree().process_frame
        await get_tree().process_frame

func _expect(condition: bool,message: String) -> void:
    if not condition:
        _failures.append(message)
