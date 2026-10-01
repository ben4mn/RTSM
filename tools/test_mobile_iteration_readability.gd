extends Node
## Settled font/Control bounds and real viewport touch ownership, beyond configured minima.
var _failures: Array[String] = []
var _moves: int = 0
var _profiles: Array[Dictionary] = []

class FakeMap extends Node2D:
    func world_to_tile(world: Vector2) -> Vector2i:
        return Vector2i(roundi(world.x/16.0),roundi(world.y/16.0))

func _ready() -> void:
    call_deferred("_run")

func _run() -> void:
    AudioManager.set_all_enabled(false)
    for phone: Vector2i in [Vector2i(844,390),Vector2i(932,430)]:
        for scale_factor: float in [1.0,1.075,1.15]:
            for notched: bool in [false,true]:
                await _profile(phone,scale_factor,notched)
    await _touch_ownership()
    var evidence := FileAccess.open("res://output/aoe-iteration/mobile-readability.json",FileAccess.WRITE)
    if evidence:
        evidence.store_string(JSON.stringify({"profiles":_profiles,"failures":_failures,"units":"Settled logical Control bounds. CSS-equivalent sizes use actual phone/logical viewport ratios; no physical phone or native density claim."},"  "))
    for failure: String in _failures:
        push_error("[FAIL] mobile_iteration_readability: "+failure)
    if _failures.is_empty():
        print("[PASS] mobile_iteration_readability: 12 profiles, full essential text, large banks, safe labels, three counter cards, projected minimap and viewport canceled/orphan/HUD/pinch ownership")
    get_tree().quit(0 if _failures.is_empty() else 1)

func _profile(phone: Vector2i, scale_factor: float, notched: bool) -> void:
    var logical := Vector2i(floori(phone.x/scale_factor),floori(phone.y/scale_factor))
    var viewport := SubViewport.new()
    viewport.size = logical
    add_child(viewport)
    var hud: CanvasLayer = load("res://scenes/ui/hud.tscn").instantiate()
    viewport.add_child(hud)
    await get_tree().process_frame
    await get_tree().process_frame
    var safe := Rect2(Vector2.ZERO,Vector2(logical))
    if notched:
        safe = Rect2(Vector2(44.0/scale_factor,0),Vector2(logical)-Vector2(88.0/scale_factor,18.0/scale_factor))
    var label := "%s scale %.3f notch %s" % [phone,scale_factor,notched]
    hud.call("update_idle_villager_count",2)
    hud.call("update_military_count",9)
    hud.call("update_villager_tasks",12,8,0,2)
    for message: String in ["Units stopped", "Need +290 food and +80 gold to age up.", "Opening complete. Grow, age up, and contest the Sacred Site."]:
        hud.call("show_notification",message,Color.WHITE)
        await _settle(hud,logical,safe)
        var feed: Control = hud.get("_notification_container")
        for toast: Control in feed.get_children():
            if toast.is_queued_for_deletion() or not toast.visible:
                continue
            var text: Label = toast.get_child(0)
            _expect(text.size.y >= text.get_theme_font("font").get_height(text.get_theme_font_size("font_size")),"%s natural notification collapsed: %s" % [label,text.text])
            _expect(text.get_line_count() == text.get_visible_line_count(),"%s notification hides lines: %s" % [label,text.text])
            _expect(safe.encloses(toast.get_global_rect()),"%s notification outside safe area" % label)
            _expect(not toast.get_global_rect().intersects((hud.get("_camera_controls") as Control).get_global_rect()),"%s notification %s (text %s, lines %d, min %s) overlaps zoom rail %s" % [label,toast.get_global_rect(),text.text,text.get_line_count(),text.custom_minimum_size,(hud.get("_camera_controls") as Control).get_global_rect()])
    for amount: int in [9999,99999,9999999]:
        hud.call("_update_resource_display",{"food":amount,"wood":amount,"gold":amount})
        hud.call("update_population",40,40)
        await _settle(hud,logical,safe)
        var utility: Control = hud.get_node("Root/GameControlButtons")
        for key: String in ["food_label","wood_label","gold_label","pop_label","age_label","game_time_label"]:
            var item: Label = hud.get(key)
            _expect(safe.encloses(item.get_global_rect()),"%s bank%d %s outside safe area: %s" % [label,amount,key,item.get_global_rect()])
            _expect(not item.get_global_rect().intersects(utility.get_global_rect()),"%s bank%d %s overlaps Pause" % [label,amount,key])
            _text_fits(item,label+" "+key)
    _expect((hud.get("_camera_view_button") as Button).visible and not (hud.get("_camera_zoom_in_button") as Button).visible,"%s view controls do not start collapsed" % label)
    var tc := BuildingBase.new()
    tc.building_type = BuildingData.BuildingType.TOWN_CENTER
    tc.player_owner = 0
    tc.state = BuildingBase.State.ACTIVE
    var queue := ProductionQueue.new()
    tc.add_child(queue)
    tc.set_production_queue(queue)
    hud.call("show_building_selection","Town Center",5000,5000,[{"unit_type":UnitData.UnitType.VILLAGER,"name":"Villager","is_training":true,"progress":0.4}],[UnitData.UnitType.VILLAGER,UnitData.UnitType.SCOUT],tc)
    await _settle(hud,logical,safe)
    var scroll: ScrollContainer = hud.get("command_scroll")
    for button: Button in (hud.get("_train_buttons_container") as HBoxContainer).get_children():
        _expect(scroll.get_global_rect().encloses(button.get_global_rect()),"%s initial TC action clipped: %s" % [label,button.name])
        _button_text_fits(button,label)
    _text_fits(hud.get("selection_name"),label)
    _text_fits(hud.get("selection_details"),label)
    _expect(not (hud.get("build_menu_button") as Button).visible and not (hud.get("_town_center_button") as Button).visible and not (hud.get("_select_military_button") as Button).visible,"%s TC retains irrelevant kingdom controls" % label)
    _expect((hud.get("age_up_button") as Button).visible and (hud.get("_selection_back_button") as Button).visible,"%s TC loses Age or Back" % label)
    var queue_hint: Label = hud.get("_queue_hint_label")
    _text_fits(queue_hint,label+" queue caption")
    _expect(queue_hint.visible,"%s queue caption missing" % label)
    _expect(safe.encloses(queue_hint.get_global_rect()),"%s queue caption outside safe area" % label)
    _expect(not queue_hint.get_global_rect().intersects((hud.get("selection_info_column") as Control).get_global_rect()),"%s queue caption overlaps selection details" % label)
    var queue_items: Array=[{"unit_type":UnitData.UnitType.VILLAGER,"name":"Villager","is_training":true,"progress":0.42}]
    for type: int in [UnitData.UnitType.VILLAGER,UnitData.UnitType.SCOUT]:
        for index: int in 14:
            queue_items.append({"unit_type":type,"name":UnitData.get_unit_name(type),"is_training":false})
    hud.call("show_building_selection","Town Center",5000,5000,queue_items,[UnitData.UnitType.VILLAGER,UnitData.UnitType.SCOUT],tc)
    await _settle(hud,logical,safe)
    scroll.scroll_horizontal=int(scroll.get_h_scroll_bar().max_value)
    await get_tree().process_frame
    await get_tree().process_frame
    for action: Control in (hud.get("queue_container") as Control).get_children():
        if action.visible and not action.is_queued_for_deletion() and action is Button:
            _expect(scroll.get_global_rect().encloses(action.get_global_rect()),"%s queue-page name/action clipped: %s %s inside %s" % [label,(action as Button).text,action.get_global_rect(),scroll.get_global_rect()])
            _button_text_fits(action as Button,label+" queue page")
    scroll.scroll_horizontal=0
    for role: int in [UnitData.UnitType.INFANTRY,UnitData.UnitType.ARCHER,UnitData.UnitType.CAVALRY]:
        hud.call("show_unit_selection",UnitData.get_unit_name(role),100,100,"ATTACKING",4,{"unit_type":role})
        hud.call("configure_unit_commands",true,true,"Aggressive","smart")
        await _settle(hud,logical,safe)
        _text_fits(hud.get("selection_name"),label)
        _text_fits(hud.get("selection_details"),label)
        _expect((hud.get("selection_panel") as Control).size.y <= 72.5,"%s counter details expand shelf" % label)
        _expect((hud.get("selection_details") as Label).text.contains(UnitData.get_unit_counter_description(role)),"%s missing visible counter" % label)
        _expect(not (hud.get("build_menu_button") as Button).visible and not (hud.get("age_up_button") as Button).visible and not (hud.get("_mobile_action_panel") as Control).visible,"%s army retains irrelevant controls" % label)
    hud.call("show_unit_selection","Villager",50,50,"Gathering Food (19/20)",1,{"unit_type":UnitData.UnitType.VILLAGER})
    hud.call("configure_unit_commands",true,false,"Aggressive","smart")
    await _settle(hud,logical,safe)
    _text_fits(hud.get("selection_details"),label)
    _expect((hud.get("build_menu_button") as Button).visible and not (hud.get("age_up_button") as Button).visible,"%s worker context loses Build or retains Age" % label)
    _expect((hud.get("_idle_villager_button") as Button).visible,"%s worker loses meaningful Idle shortcut" % label)
    var task_caption: HBoxContainer=hud.get("_villager_task_hbox")
    _expect(task_caption.visible,"%s worker distribution missing" % label)
    for task_text: Label in task_caption.get_children():
        if task_text.visible:
            _text_fits(task_text,label+" worker counts")
    _expect(safe.encloses(task_caption.get_global_rect()),"%s worker counts outside safe area" % label)
    hud.call("clear_selection")
    await _settle(hud,logical,safe)
    _expect((hud.get("_town_center_button") as Button).visible and (hud.get("_select_military_button") as Button).visible and (hud.get("build_menu_button") as Button).visible,"%s unselected kingdom controls do not restore" % label)
    (hud.get("_camera_view_button") as Button).pressed.emit()
    await _settle(hud,logical,safe)
    _expect((hud.get("_camera_zoom_in_button") as Button).visible,"%s View does not reveal zoom controls" % label)
    for camera_action: Button in (hud.get("_camera_controls") as HBoxContainer).get_children():
        if camera_action.visible:
            _expect(camera_action.size.x>=48 and camera_action.size.y>=48,"%s expanded camera target under48" % label)
    (hud.get("_camera_view_button") as Button).pressed.emit()
    await _settle(hud,logical,safe)
    var grid: Array = []
    for y: int in MapData.MAP_HEIGHT:
        var row: Array = []
        for x: int in MapData.MAP_WIDTH:
            row.append(MapData.TileType.GRASS)
        grid.append(row)
    var center := Vector2(0,MapData.MAP_HEIGHT*16)
    hud.call("update_minimap",grid,[],[],[],[],Rect2(center-Vector2(422,195),Vector2(844,390)))
    var image: Image = hud.get("_minimap_image")
    var ymin: int = image.get_height()
    var ymax: int = 0
    for y: int in image.get_height():
        for x: int in image.get_width():
            var color: Color = image.get_pixel(x,y)
            if color.r > 0.9 and color.g > 0.9 and color.b > 0.9:
                ymin = mini(ymin,y)
                ymax = maxi(ymax,y)
    _expect(ymax-ymin >= 15,"%s camera minimap outline collapsed into stripe" % label)
    var caption: Label = hud.get("_minimap_hint_label")
    _text_fits(caption,label+" minimap caption")
    _expect(not caption.get_global_rect().intersects((hud.get("_camera_controls") as Control).get_global_rect()),"%s map caption overlaps zoom" % label)
    _profiles.append({"profile":label,"logical_viewport":str(logical),"safe":str(safe),"details":(hud.get("selection_details") as Label).text,"shelf":str((hud.get("selection_panel") as Control).get_global_rect()),"hit_targets":hud.get("touch_target_diagnostics"),"render_to_css_ratio":Vector2(phone)/Vector2(logical)})
    tc.free()
    viewport.free()
    await get_tree().process_frame

func _settle(hud: Node,logical: Vector2i,safe: Rect2) -> void:
    await get_tree().process_frame
    await get_tree().process_frame
    hud.call("apply_mobile_layout",Vector2(logical),safe)
    await get_tree().process_frame
    await get_tree().process_frame

func _text_fits(label: Label,profile: String) -> void:
    var font: Font = label.get_theme_font("font")
    for line: String in label.text.split("\n"):
        var width: float = font.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,label.get_theme_font_size("font_size")).x
        _expect(width <= label.size.x+0.5,"%s text '%s' needs%.1fpx, has%.1f" % [profile,line,width,label.size.x])
    _expect(label.get_minimum_size().y <= label.size.y+0.5,"%s text height clipped" % profile)

func _button_text_fits(button: Button,profile: String) -> void:
    var style: StyleBox = button.get_theme_stylebox("normal")
    var available: float = button.size.x-style.get_minimum_size().x
    for line: String in button.text.split("\n"):
        var width: float = button.get_theme_font("font").get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,button.get_theme_font_size("font_size")).x
        _expect(width <= available+0.5,"%s card '%s' hides words (%.1f/%.1f)" % [profile,line,width,available])

func _touch_ownership() -> void:
    var viewport := SubViewport.new()
    viewport.size = Vector2i(844,390)
    add_child(viewport)
    var map := FakeMap.new()
    viewport.add_child(map)
    var selection := SelectionManager.new()
    selection.game_map = map
    selection.touch_context_enabled = false
    map.add_child(selection)
    var soldier: UnitBase = load("res://scenes/units/infantry.tscn").instantiate()
    map.add_child(soldier)
    soldier.set_process(false)
    selection.select_single(soldier)
    selection.move_command.connect(func(_tile: Vector2i) -> void: _moves += 1)
    var hud: CanvasLayer = load("res://scenes/ui/hud.tscn").instantiate()
    viewport.add_child(hud)
    await get_tree().process_frame
    await get_tree().process_frame
    var ground := Vector2(400,190)
    _touch(viewport,0,ground,true)
    _touch(viewport,0,ground,false,true)
    _expect(_moves==0,"OS-canceled contact issues world order")
    selection.cancel_touch_gesture()
    _touch(viewport,0,ground,false)
    _expect(_moves==0,"orphan release issues world order")
    var button: Button = hud.get("build_menu_button")
    _touch(viewport,0,button.get_global_rect().get_center(),true)
    _touch(viewport,0,ground,false)
    _expect(_moves==0,"GUI-owned press released on world issues order")
    for press_order: Vector2i in [Vector2i(0,1),Vector2i(1,0)]:
        for release_order: Vector2i in [Vector2i(0,1),Vector2i(1,0)]:
            var points: Array[Vector2] = [ground,ground+Vector2(60,0)]
            _touch(viewport,press_order.x,points[press_order.x],true)
            _touch(viewport,press_order.y,points[press_order.y],true)
            _touch(viewport,release_order.x,points[release_order.x],false)
            _touch(viewport,release_order.y,points[release_order.y],false)
    _expect(_moves==0,"pinch press/release order leaks command")
    _touch(viewport,0,ground,true)
    _touch(viewport,0,ground,false)
    _expect(_moves==1,"normal tap does not recover after canceled/HUD/pinch sequence")
    viewport.free()
    await get_tree().process_frame

func _touch(viewport: SubViewport,index: int,position: Vector2,pressed: bool,canceled: bool=false) -> void:
    var event := InputEventScreenTouch.new()
    event.index=index
    event.position=position
    event.pressed=pressed
    event.canceled=canceled
    viewport.push_input(event,true)

func _expect(condition: bool,message: String) -> void:
    if not condition:
        _failures.append(message)
