extends Node
## Frozen real-scene visual fixtures. These screenshots are layout evidence, not paid match evidence.
const STATES: Array[String] = ["unselected","worker","tc","tc_repeat","military_production","warrior","archer","horseman","mixed_army","commands","view_expanded","build_economy","build_army","placement_invalid","placement_valid","pause","results"]
const WORKER_STATUS_FIXTURES: Dictionary = {"worker_idle":"Idle", "worker_move":"Moving", "worker_retreat":"Retreating", "worker_shelter":"Sheltering", "worker_seek":"Seeking Food", "worker_gather":"Gathering Food", "worker_return":"Returning Wood", "worker_wait":"Waiting for drop-off", "worker_build":"Building", "worker_mixed":"Mixed tasks", "worker_armed":"Returning Wood"}
var _states: Array[String] = STATES.duplicate()
var _records: Array[Dictionary] = []
var _queue_records: Array[Dictionary] = []
var _output: String = "res://output/aoe-iteration/mobile-matrix"

func _ready() -> void:
    call_deferred("_run")

func _run() -> void:
    AudioManager.set_all_enabled(false)
    for argument: String in OS.get_cmdline_user_args():
        if argument.begins_with("--output="):
            _output = argument.trim_prefix("--output=")
        elif argument == "--worker-mechanics":
            _states.assign(WORKER_STATUS_FIXTURES.keys())
            _states.append("tc")
    DirAccess.make_dir_recursive_absolute(_output)
    for phone: Vector2i in [Vector2i(844,390),Vector2i(932,430)]:
        for interface_scale: float in [1.0,1.075]:
            await _profile(phone,interface_scale)
    var file := FileAccess.open(_output+"/manifest.json",FileAccess.WRITE)
    file.store_string(JSON.stringify({"evidence":"Actual root Window renders at requested phone pixels and UI scale, with project844x390 canvas_items/expand stretch. Production main scene is frozen with synthetic queue, economy banks, armies and safe-area insets to stress UI; no balance or paid-match claim.","profiles":_records,"supplementary_queue_pages":_queue_records},"  "))
    print("[PASS] mobile_iteration_matrix: ",_records.size()," rendered states (two phones, Standard/Large, three zooms), manifest with settled Control bounds")
    get_tree().quit()

func _profile(phone: Vector2i,interface_scale: float) -> void:
    get_window().size=phone
    get_window().content_scale_size=Vector2i(844,390)
    get_window().content_scale_factor=interface_scale
    await get_tree().process_frame
    await get_tree().process_frame
    var viewport: Viewport=get_viewport()
    var logical: Vector2=viewport.get_visible_rect().size
    var surface_transform: Transform2D=viewport.get_final_transform()
    var css_scale:=Vector2(surface_transform.x.length(),surface_transform.y.length())
    GameManager.guided_opening_enabled = false
    GameManager.selected_population_limit = 30
    GameManager.selected_map_seed = 101
    var main: Node = load("res://scenes/main/main.tscn").instantiate()
    add_child(main)
    for frame: int in 900:
        if main.get("_building_placement") != null and GameManager.current_state == GameManager.GameState.PLAYING:
            break
        await get_tree().process_frame
    var map: Node2D = main.get_node("GameMap")
    var camera: Camera2D = map.get("camera")
    var hud: CanvasLayer = main.get_node("HUD")
    var tc: BuildingBase = main.get("_player_buildings")[0][0]
    GameManager.players[0]["age"] = 2
    hud.call("_update_age_display")
    var center: Vector2 = tc.global_position+Vector2(180,0)
    camera.position = center
    camera.reset_smoothing()
    camera.force_update_scroll()
    GameManager.players[0]["population_cap"] = 30
    var warriors: Array[UnitBase] = []
    var all_soldiers: Array[UnitBase] = []
    for role: int in [UnitData.UnitType.INFANTRY,UnitData.UnitType.ARCHER,UnitData.UnitType.CAVALRY]:
        for index: int in 3:
            var troop: UnitBase = main.call("_spawn_unit",role,0,center+Vector2(80+(role-1)*60,(index-1)*36))
            all_soldiers.append(troop)
            if role == UnitData.UnitType.INFANTRY:
                warriors.append(troop)
    main.call("_update_fog_of_war")
    await get_tree().process_frame
    get_tree().paused = true
    var safe := Rect2(Vector2(44.0/css_scale.x,0),logical-Vector2(88.0/css_scale.x,18.0/css_scale.y))
    var menu: Node = main.get("_build_menu")
    var placement: Node2D = main.get("_building_placement")
    var result_screen: CanvasLayer = load("res://scenes/ui/game_over_screen.tscn").instantiate()
    result_screen.process_mode = Node.PROCESS_MODE_ALWAYS
    main.add_child(result_screen)
    var queue := tc.get_production_queue()
    var production_fixture: BuildingBase=null
    queue.auto_queue_unit_type = UnitData.UnitType.VILLAGER
    var queue_items: Array = [{"unit_type":UnitData.UnitType.VILLAGER,"name":"Villager","is_training":true,"progress":0.42},{"unit_type":UnitData.UnitType.VILLAGER,"name":"Villager","is_training":false},{"unit_type":UnitData.UnitType.SCOUT,"name":"Scout","is_training":false}]
    var prefix := "%dx%d-%s" % [phone.x,phone.y,"standard" if interface_scale==1.0 else "large"]
    for zoom_name: String in ["overview","default","detail"]:
        var zoom: float = float(map.call("get_zoom_state")["min" if zoom_name=="overview" else ("max" if zoom_name=="detail" else "default")])
        camera.zoom = Vector2(zoom,zoom)
        camera.position = center
        camera.reset_smoothing()
        camera.force_update_scroll()
        hud.call("update_camera_zoom",zoom,float(map.call("get_zoom_state")["min"]),float(map.call("get_zoom_state")["max"]))
        for state: String in _states:
            hud.set("_camera_controls_expanded",state=="view_expanded")
            for toast: Node in (hud.get("_notification_container") as Control).get_children():
                hud.call("_retire_dynamic_control",toast)
            hud.call("set_ui_modal_state",0)
            menu.call("close_menu")
            if placement.get("active"):
                placement.call("cancel_placement")
            hud.call("set_placement_mode",false)
            hud.call("clear_selection")
            hud.call("set_progression_hint","")
            hud.call("set_early_game_ui_state",false)
            hud.call("update_idle_villager_count",2)
            hud.call("update_military_count",9)
            hud.call("update_villager_tasks",12,8,0,2)
            hud.call("_update_resource_display",{"food":99999,"wood":9999999,"gold":9999})
            hud.call("update_population",29,30)
            hud.call("set_minimap_hint","Map · tap to view")
            hud.call("update_sacred_site_timer",1,492.0,600.0)
            if WORKER_STATUS_FIXTURES.has(state):
                var cargo_type: String = "food" if state in ["worker_seek", "worker_gather"] else "wood"
                var cargo_count: int = 10
                var capacity: int = 10
                if state=="worker_mixed":
                    cargo_type="mixed"
                    capacity=80
                hud.call("show_unit_selection","Villager",17,25,WORKER_STATUS_FIXTURES[state],8 if state=="worker_mixed" else 1,{"unit_type":UnitData.UnitType.VILLAGER,"cargo_amount":cargo_count,"cargo_capacity":capacity,"cargo_resource":cargo_type})
                hud.call("configure_unit_commands",true,false,"Aggressive","move" if state=="worker_armed" else "smart")
            elif state=="worker":
                hud.call("show_notification","Need +290 food and +80 gold to age up.",Color(1.0,0.5,0.35))
                hud.call("show_notification","Opening complete. Grow, age up, and contest the Sacred Site.",Color(0.68,0.86,1.0))
                hud.call("show_unit_selection","Villager",50,50,"Gathering Food (19/20)",1,{"unit_type":UnitData.UnitType.VILLAGER})
                hud.call("configure_unit_commands",true,false,"Aggressive","smart")
            elif state in ["tc","tc_repeat"]:
                queue.auto_queue_enabled = state=="tc_repeat"
                hud.call("show_building_selection","Town Center",5000,5000,queue_items,[UnitData.UnitType.VILLAGER,UnitData.UnitType.SCOUT],tc)
            elif state=="military_production":
                if production_fixture==null:
                    production_fixture=load("res://scenes/buildings/barracks.tscn").instantiate()
                    production_fixture.player_owner=0
                    production_fixture.position=tc.position+Vector2(160,80)
                    map.add_child(production_fixture)
                    production_fixture.state=BuildingBase.State.ACTIVE
                hud.call("show_building_selection","Barracks",1200,1200,[],[UnitData.UnitType.INFANTRY],production_fixture)
            elif state in ["warrior","archer","horseman","mixed_army","commands"]:
                var role: int = UnitData.UnitType.INFANTRY if state=="warrior" else (UnitData.UnitType.ARCHER if state=="archer" else UnitData.UnitType.CAVALRY)
                var stats: Dictionary = {"unit_type":role}
                var name: String = UnitData.get_unit_name(role)
                var count: int = 3
                if state in ["mixed_army","commands"]:
                    name="Army"
                    count=9
                    stats={"role_counts":{UnitData.UnitType.INFANTRY:3,UnitData.UnitType.ARCHER:3,UnitData.UnitType.CAVALRY:3}}
                hud.call("show_unit_selection",name,300,330,"MOVING",count,stats)
                hud.call("configure_unit_commands",true,true,"Aggressive","attack_move" if state=="commands" else "smart")
                if state=="commands":
                    hud.call("_on_unit_more_pressed")
            elif state.begins_with("build_"):
                menu.set("_last_selected_building_type",BuildingData.BuildingType.HOUSE)
                hud.call("set_ui_modal_state",1)
                menu.call("update_age",2)
                menu.call("update_resources",{"food":99999,"wood":9999999,"gold":9999})
                menu.call("open_menu")
                menu.call("_on_category_pressed","Army" if state=="build_army" else "Economy")
            elif state.begins_with("placement_"):
                placement.call("start_placement",BuildingData.BuildingType.HOUSE)
                hud.call("set_placement_mode",true,"House")
                placement.call("update_preview_at_world",tc.global_position if state=="placement_invalid" else center+Vector2(100,80))
                hud.call("update_placement_preview",state=="placement_valid","Ready" if state=="placement_valid" else "Occupied by Town Center")
            elif state=="pause":
                hud.call("set_ui_modal_state",2)
            elif state=="results":
                var results: CanvasLayer = result_screen
                results.call("show_defeat",{"victory_reason":"Town Center destroyed","game_time":"12:18","player_age":2,"ai_age":3,"score":1024,"ai_score":2408,"army_trained":19,"ai_army_trained":31,"units_lost":15,"ai_units_lost":11,"resources_gathered":199999,"ai_resources_gathered":299999,"sacred_control_seconds":492,"ai_sacred_control_seconds":591})
                results.call("_fit_panel_to_size",Vector2(logical),safe)
                await get_tree().create_timer(0.45,true,false,true).timeout
            await get_tree().process_frame
            await get_tree().process_frame
            hud.call("apply_mobile_layout",Vector2(logical),safe)
            menu.call("set_safe_area_rect",safe)
            main.call("_update_minimap")
            await get_tree().process_frame
            await RenderingServer.frame_post_draw
            var bitmap: Image = viewport.get_texture().get_image()
            assert(bitmap.get_size()==phone,"Root viewport capture differs from actual requested phone pixels")
            var filename: String = prefix+"-"+zoom_name+"-"+state+".png"
            bitmap.save_png(_output+"/"+filename)
            hud.call("_refresh_touch_target_diagnostics")
            _records.append({"image":filename,"phone":str(phone),"interface_scale":interface_scale,"zoom":zoom,"zoom_name":zoom_name,"state":state,"safe_logical":str(safe),"logical_viewport":str(logical),"native_final_transform":str(surface_transform),"native_surface_scale":str(css_scale),"logical_to_css_ratio":str(Vector2(phone)/Vector2(logical)),"hit_targets":hud.get("touch_target_diagnostics"),"visible_text_and_hit_rects":_capture_controls(main),"selection_name":(hud.get("selection_name") as Label).text,"selection_details":(hud.get("selection_details") as Label).text})
            if state=="tc_repeat":
                var crowded_queue: Array=[{"unit_type":UnitData.UnitType.VILLAGER,"name":"Villager","is_training":true,"progress":0.42}]
                for queued_type: int in [UnitData.UnitType.VILLAGER,UnitData.UnitType.SCOUT]:
                    for item_index: int in 14:
                        crowded_queue.append({"unit_type":queued_type,"name":UnitData.get_unit_name(queued_type),"is_training":false})
                hud.call("show_building_selection","Town Center",5000,5000,crowded_queue,[UnitData.UnitType.VILLAGER,UnitData.UnitType.SCOUT],tc)
                for settle_frame: int in 4:
                    hud.call("apply_mobile_layout",logical,safe)
                    await get_tree().process_frame
                var shelf: ScrollContainer=hud.get("command_scroll")
                shelf.scroll_horizontal=int(shelf.get_h_scroll_bar().max_value)
                await get_tree().process_frame
                await RenderingServer.frame_post_draw
                var queue_image: Image=viewport.get_texture().get_image()
                assert(queue_image.get_size()==phone,"Queue capture differs from actual phone pixels")
                var queue_file: String=prefix+"-"+zoom_name+"-queue_page.png"
                queue_image.save_png(_output+"/"+queue_file)
                _queue_records.append({"image":queue_file,"synthetic_waiting_counts":{"Villager":14,"Scout":14},"visible_text_and_hit_rects":_capture_controls(main),"scroll_horizontal":shelf.scroll_horizontal,"logical_to_css_ratio":str(Vector2(phone)/Vector2(logical))})
                shelf.scroll_horizontal=0
            if state=="results":
                result_screen.visible=false
            print("Captured ",filename)
    get_tree().paused=false
    main.free()
    await get_tree().process_frame

func _capture_controls(node: Node) -> Array[Dictionary]:
    var records: Array[Dictionary] = []
    if node is Control and (node is Label or node is BaseButton) and (node as Control).is_visible_in_tree():
        var control := node as Control
        var rect := control.get_global_rect()
        var clipped := rect
        var ancestor := control.get_parent()
        while ancestor != null:
            if ancestor is ScrollContainer:
                clipped = clipped.intersection((ancestor as Control).get_global_rect())
            ancestor = ancestor.get_parent()
        var label_text: String = str(control.get("text")) if node is Label or node is Button else ""
        var font_size: int = control.get_theme_font_size("font_size")
        var line_widths: Array[float] = []
        for line: String in label_text.split("\n"):
            line_widths.append(control.get_theme_font("font").get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x)
        records.append({"path":str(control.get_path()),"kind":control.get_class(),"text":label_text,"font_size":font_size,"logical_rect":str(rect),"scroll_clipped_rect":str(clipped),"actual_width":control.size.x,"actual_height":control.size.y,"unwrapped_line_widths":line_widths,"interactive":node is BaseButton,"disabled":(node as BaseButton).disabled if node is BaseButton else false})
    for child: Node in node.get_children():
        records.append_array(_capture_controls(child))
    return records
