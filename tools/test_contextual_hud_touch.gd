extends Node
## Real Input.parse touch dispatch through contextual controls in the production match.
var _failures: Array[String]=[]
var _orders: int=0
func _ready() -> void:
    call_deferred("_run")
func _run() -> void:
    AudioManager.set_all_enabled(false)
    Input.emulate_mouse_from_touch=true
    for phone: Vector2i in [Vector2i(844,390),Vector2i(932,430)]:
        for scale_factor: float in [1.0,1.075]:
            await _profile(phone,scale_factor)
    for failure: String in _failures:
        push_error("[FAIL] contextual_hud_touch: "+failure)
    if _failures.is_empty():
        print("[PASS] contextual_hud_touch: four actual phone/scale dispatch profiles; View/More/Clear/Back own touches; hidden Home area reaches world; worker/army/TC controls restore")
    get_tree().quit(0 if _failures.is_empty() else 1)
func _profile(phone: Vector2i,scale_factor: float) -> void:
    get_window().size=phone
    get_window().content_scale_size=Vector2i(844,390)
    get_window().content_scale_factor=scale_factor
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
    var selection: SelectionManager=map.get_node("SelectionManager")
    var tc: BuildingBase=main.get("_player_buildings")[0][0]
    var villager: UnitBase=main.get("_player_units")[0][0]
    GameManager.players[0]["population_cap"]=30
    var soldier: UnitBase=main.call("_spawn_unit",UnitData.UnitType.INFANTRY,0,tc.global_position+Vector2(120,20))
    selection.move_command.connect(func(_tile: Vector2i) -> void: _orders+=1)
    await _settle()
    var profile: String="%s scale%.3f" % [phone,scale_factor]
    var former_home: Vector2=(hud.get("_town_center_button") as Button).get_global_rect().get_center()
    selection.select_single(soldier)
    await _settle()
    _expect(not (hud.get("build_menu_button") as Button).is_visible_in_tree() and not (hud.get("age_up_button") as Button).is_visible_in_tree() and not (hud.get("_town_center_button") as Button).is_visible_in_tree(),profile+" army retains kingdom controls")
    var before: int=_orders
    await _tap((hud.get("_camera_view_button") as Button).get_global_rect().get_center())
    _expect((hud.get("_camera_zoom_in_button") as Button).is_visible_in_tree(),profile+" View touch does not open zoom")
    await _tap((hud.get("_camera_view_button") as Button).get_global_rect().get_center())
    _expect(not (hud.get("_camera_zoom_in_button") as Button).is_visible_in_tree(),profile+" View touch does not collapse zoom")
    await _tap((hud.get("_unit_more_button") as Button).get_global_rect().get_center())
    _expect((hud.get("_advanced_command_panel") as Control).is_visible_in_tree(),profile+" More touch does not open orders")
    _expect(_orders==before,profile+" visible HUD touch issued world order")
    await _tap((hud.get("_unit_more_button") as Button).get_global_rect().get_center())
    await _tap(former_home)
    _expect(_orders>before,profile+" hidden Home area consumes world touch")
    var hidden_area_orders: int=_orders-before
    selection.select_single(soldier)
    await _settle()
    before=_orders
    var clear: Button=hud.get("_unit_clear_button")
    await _tap(clear.get_global_rect().get_center(),0.55)
    _expect(selection.selected.is_empty() and not bool(hud.get("_selection_context_active")),profile+" Clear touch does not restore unselected state")
    _expect((hud.get("_town_center_button") as Button).is_visible_in_tree() and (hud.get("build_menu_button") as Button).is_visible_in_tree(),profile+" kingdom controls do not return after Clear")
    _expect(_orders==before,profile+" Clear leaks world order")
    selection.select_single(villager)
    await _settle()
    _expect((hud.get("build_menu_button") as Button).is_visible_in_tree() and not (hud.get("age_up_button") as Button).is_visible_in_tree(),profile+" worker context is wrong")
    _expect((hud.get("_villager_task_hbox") as Control).is_visible_in_tree(),profile+" worker distribution caption is hidden")
    selection.select_single(tc)
    await _settle()
    _expect((hud.get("age_up_button") as Button).is_visible_in_tree() and not (hud.get("build_menu_button") as Button).is_visible_in_tree(),profile+" Town Center context is wrong")
    before=_orders
    await _tap((hud.get("_selection_back_button") as Button).get_global_rect().get_center())
    _expect(not bool(hud.get("_selection_context_active")) and (hud.get("_town_center_button") as Button).is_visible_in_tree(),profile+" Back does not restore kingdom controls")
    _expect(_orders==before,profile+" Back leaks world order")
    print("Context dispatch: ",profile," logical viewport=",get_viewport().get_visible_rect().size," former hidden Home world orders=",hidden_area_orders)
    main.free()
    await get_tree().process_frame
func _settle() -> void:
    for frame: int in 4:
        await get_tree().process_frame
func _tap(position: Vector2,hold_seconds: float=0.0) -> void:
    for pressed: bool in [true,false]:
        var touch:=InputEventScreenTouch.new()
        touch.index=0
        touch.position=get_viewport().get_final_transform()*position
        touch.pressed=pressed
        Input.parse_input_event(touch)
        await _settle()
        if pressed and hold_seconds>0.0:
            await get_tree().create_timer(hold_seconds).timeout
func _expect(condition: bool,message: String) -> void:
    if not condition:
        _failures.append(message)
