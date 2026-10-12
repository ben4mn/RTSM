extends Node
## Settled font/Control bounds and real viewport touch ownership, beyond configured minima.
var _failures: Array[String] = []
var _moves: int = 0
var _profiles: Array[Dictionary] = []
var _selection_revision: int = 0

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
    var evidence_path: String = OS.get_environment("AOEM_READABILITY_EVIDENCE")
    if evidence_path.is_empty():
        evidence_path = "res://output/aoe-iteration/mobile-readability.json"
    var evidence := FileAccess.open(evidence_path,FileAccess.WRITE)
    if evidence:
        evidence.store_string(JSON.stringify({"profiles":_profiles,"failures":_failures,"units":"Settled logical Control bounds. CSS-equivalent sizes use actual phone/logical viewport ratios; no physical phone or native density claim."},"  "))
    for failure: String in _failures:
        push_error("[FAIL] mobile_iteration_readability: "+failure)
    if _failures.is_empty():
        print("[PASS] mobile_iteration_readability: 12 profiles, all six production names/costs/roles/max queue badges, worker/army/foundation density, full essential text, large banks, safe labels, projected minimap and viewport canceled/orphan/HUD/pinch ownership")
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
        var utility: Control = hud.get("_pause_button")
        for key: String in ["food_label","wood_label","gold_label","pop_label","age_label","game_time_label"]:
            var item: Label = hud.get(key)
            if not item.is_visible_in_tree():
                continue
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
    _publish_selection_change(hud)
    hud.call("show_building_selection","Town Center",5000,5000,[{"unit_type":UnitData.UnitType.VILLAGER,"name":"Villager","is_training":true,"progress":0.4}],[UnitData.UnitType.VILLAGER,UnitData.UnitType.SCOUT],tc)
    await _settle(hud,logical,safe)
    var scroll: ScrollContainer = hud.get("command_scroll")
    for button: Button in (hud.get("_train_buttons_container") as HBoxContainer).get_children():
        _expect(scroll.get_global_rect().encloses(button.get_global_rect()),"%s initial TC action clipped: %s" % [label,button.name])
        _button_text_fits(button,label)
    await _selection_name_readable(hud,logical,safe,label)
    _text_fits(hud.get("selection_details"),label)
    _expect(not (hud.get("build_menu_button") as Button).visible and not (hud.get("_town_center_button") as Button).visible and not (hud.get("_select_military_button") as Button).visible,"%s TC retains irrelevant kingdom controls" % label)
    _expect((hud.get("age_up_button") as Button).visible and (hud.get("_selection_back_button") as Button).visible,"%s TC loses Age or Back" % label)
    var queue_navigation: Button = hud.get("_queue_navigation_button")
    _button_text_fits(queue_navigation,label+" queue navigation")
    _expect(queue_navigation.visible and not queue_navigation.disabled,"%s queue navigation missing or disabled" % label)
    _expect(queue_navigation.size.x >= 48.0 and queue_navigation.size.y >= 48.0,"%s queue navigation target under48px" % label)
    _expect((hud.get("selection_panel") as Control).get_global_rect().encloses(queue_navigation.get_global_rect()),"%s queue navigation floats outside shelf" % label)
    _expect((hud.get("selection_panel") as Control).size.y <= 72.5,"%s production shelf grows beyond72px" % label)
    _expect((hud.get("selection_panel") as Control).size.x <= 420.0,"%s TC recruitment shelf retains empty width: %.1f" % [label,(hud.get("selection_panel") as Control).size.x])
    _expect(safe.encloses(queue_navigation.get_global_rect()),"%s queue navigation outside safe area" % label)
    _expect(not queue_navigation.get_global_rect().intersects((hud.get("selection_info_column") as Control).get_global_rect()),"%s queue navigation overlaps selection details" % label)
    _expect(queue_navigation.get_node("CommandIconBadge").text == "1","%s initial queue count missing" % label)
    _expect((hud.get("selection_details") as Label).text.to_lower().contains("rally") and (hud.get("selection_details") as Label).text.contains("40%"),"%s compact production loses rally cue or training progress: %s" % [label,(hud.get("selection_details") as Label).text])
    var production_details: Label = hud.get("selection_details")
    var details_height: float = production_details.get_theme_font("font").get_height(production_details.get_theme_font_size("font_size")) * float(production_details.text.split("\n").size())
    _expect(production_details.size.y >= details_height,"%s compact production hides rally/progress lines: %.1f needs %.1f" % [label,production_details.size.y,details_height])
    var queue_items: Array=[{"unit_type":UnitData.UnitType.VILLAGER,"name":"Villager","is_training":true,"progress":0.42}]
    for type: int in [UnitData.UnitType.VILLAGER,UnitData.UnitType.SCOUT]:
        for index: int in 14:
            queue_items.append({"unit_type":type,"name":UnitData.get_unit_name(type),"is_training":false})
    hud.call("show_building_selection","Town Center",5000,5000,queue_items,[UnitData.UnitType.VILLAGER,UnitData.UnitType.SCOUT],tc)
    await _settle(hud,logical,safe)
    await _tap_control(hud,queue_navigation)
    await _settle(hud,logical,safe)
    for action: Control in (hud.get("queue_container") as Control).get_children():
        if action.visible and not action.is_queued_for_deletion() and action is Button:
            _expect(scroll.get_global_rect().encloses(action.get_global_rect()),"%s queue-page name/action clipped: %s %s inside %s" % [label,(action as Button).text,action.get_global_rect(),scroll.get_global_rect()])
            _button_text_fits(action as Button,label+" queue page")
    _expect(queue_navigation.accessibility_name.contains("recruitment"),"%s queue navigation does not offer return to training" % label)
    _expect((hud.get("selection_panel") as Control).get_global_rect().encloses(queue_navigation.get_global_rect()),"%s Train return floats outside queue shelf" % label)
    await _tap_control(hud,queue_navigation)
    _expect(scroll.scroll_horizontal == 0,"%s queue navigation does not return to training" % label)
    var production_units: Array[Dictionary] = await _all_production_unit_text(hud,logical,safe,label)
    var context_shelves: Array[Dictionary] = await _non_production_shelf_density(hud,logical,safe,label)
    for role: int in [UnitData.UnitType.INFANTRY,UnitData.UnitType.ARCHER,UnitData.UnitType.CAVALRY]:
        _publish_selection_change(hud)
        hud.call("show_unit_selection",UnitData.get_unit_name(role),100,100,"ATTACKING",4,{"unit_type":role})
        hud.call("configure_unit_commands",true,true,"Aggressive","smart")
        await _settle(hud,logical,safe)
        await _selection_name_readable(hud,logical,safe,label)
        _text_fits(hud.get("selection_details"),label)
        _expect((hud.get("selection_panel") as Control).size.y <= 72.5,"%s counter details expand shelf" % label)
        _expect((hud.get("selection_details") as Label).text.contains(UnitData.get_unit_counter_description(role)),"%s missing visible counter" % label)
        _expect(not (hud.get("build_menu_button") as Button).visible and not (hud.get("age_up_button") as Button).visible and not (hud.get("_mobile_action_panel") as Control).visible,"%s army retains irrelevant controls" % label)
    _publish_selection_change(hud)
    hud.call("show_unit_selection","Villager",50,50,"Gathering Food (19/20)",1,{"unit_type":UnitData.UnitType.VILLAGER})
    hud.call("configure_unit_commands",true,false,"Aggressive","smart")
    await _settle(hud,logical,safe)
    _text_fits(hud.get("selection_details"),label)
    _expect((hud.get("build_menu_button") as Button).visible and not (hud.get("age_up_button") as Button).visible,"%s worker context loses Build or retains Age" % label)
    (hud.get("_unit_more_button") as Button).pressed.emit()
    await _settle(hud,logical,safe)
    var worker_idle: Button = hud.get("_worker_idle_button")
    _expect(worker_idle.is_visible_in_tree() and worker_idle.icon != null and worker_idle.get_node("CommandIconBadge").text == "2","%s worker More loses Idle shortcut/count" % label)
    _expect(worker_idle.size.x >= 48 and worker_idle.size.y >= 48,"%s worker Idle target under48" % label)
    (hud.get("_unit_more_button") as Button).pressed.emit()
    await _settle(hud,logical,safe)
    var task_caption: HBoxContainer=hud.get("_villager_task_hbox")
    _expect(task_caption.visible,"%s worker distribution missing" % label)
    for task_text: Label in task_caption.get_children():
        if task_text.visible:
            _text_fits(task_text,label+" worker counts")
    _expect(safe.encloses(task_caption.get_global_rect()),"%s worker counts outside safe area" % label)
    _publish_selection_change(hud)
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
    _expect((hud.get("minimap_bg") as Control).get_global_rect().encloses(caption.get_global_rect()),"%s caption extends beyond minimap" % label)
    _expect(not caption.get_global_rect().intersects((hud.get("_camera_controls") as Control).get_global_rect()),"%s map caption overlaps zoom" % label)
    _profiles.append({"profile":label,"logical_viewport":str(logical),"safe":str(safe),"details":(hud.get("selection_details") as Label).text,"shelf":str((hud.get("selection_panel") as Control).get_global_rect()),"production_units":production_units,"context_shelves":context_shelves,"hit_targets":hud.get("touch_target_diagnostics"),"render_to_css_ratio":Vector2(phone)/Vector2(logical)})
    tc.free()
    viewport.free()
    await get_tree().process_frame

func _settle(hud: Node,logical: Vector2i,safe: Rect2) -> void:
    await get_tree().process_frame
    await get_tree().process_frame
    hud.call("apply_mobile_layout",Vector2(logical),safe)
    await get_tree().process_frame
    await get_tree().process_frame

func _publish_selection_change(hud: Node) -> void:
    _selection_revision += 1
    hud.call("set_selection_context_revision",_selection_revision)

func _tap_control(hud: Node,control: Control) -> void:
    var viewport: SubViewport = hud.get_viewport() as SubViewport
    for pressed: bool in [true,false]:
        var event := InputEventMouseButton.new()
        event.position = control.get_global_rect().get_center()
        event.global_position = event.position
        event.button_index = MOUSE_BUTTON_LEFT
        event.pressed = pressed
        viewport.push_input(event,true)
        await get_tree().process_frame
    await get_tree().process_frame

func _selection_name_readable(hud: Node,logical: Vector2i,safe: Rect2,profile: String) -> void:
    var name_label: Label = hud.get("selection_name")
    var font: Font = name_label.get_theme_font("font")
    var overflows: bool = false
    for line: String in name_label.text.split("\n"):
        overflows = overflows or font.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,name_label.get_theme_font_size("font_size")).x > name_label.size.x+0.5
    if not overflows:
        _text_fits(name_label,profile)
        return
    _expect(name_label.text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS,profile+" long selection name loses visible ellipsis")
    _expect(name_label.get_minimum_size().y <= name_label.size.y+0.5,profile+" selection identity clips vertically")
    var full_name: String = hud.get("_selection_full_name")
    var info: Button = hud.get("_selection_info_button")
    _expect(info.is_visible_in_tree() and info.size.x >= 48.0 and info.size.y >= 48.0 and safe.encloses(info.get_global_rect()),profile+" truncated name lacks safe48px tap Info")
    await _tap_control(hud,info)
    await _settle(hud,logical,safe)
    var panel: Control = hud.get("_info_panel")
    var title: Label = hud.get("_info_title")
    _expect(hud.call("get_secondary_surface_name") == "info" and panel.is_visible_in_tree(),profile+" tap Info does not disclose full identity")
    _expect(title.text == full_name,profile+" tap Info loses complete selection identity")
    _text_fits(title,profile+" full Info identity")
    _expect((hud.call("get_hold_safe_rect") as Rect2).encloses(panel.get_global_rect()),profile+" identity Info escapes rail-reserved safe area")
    var close: Button = panel.find_child("InfoCloseButton",true,false) as Button
    _expect(close.size.x >= 48.0 and close.size.y >= 48.0 and panel.get_global_rect().encloses(close.get_global_rect()),profile+" identity Info Close is inaccessible")
    await _tap_control(hud,close)
    await _settle(hud,logical,safe)
    _expect(hud.call("get_secondary_surface_name") == "none",profile+" identity Info does not close by actual tap")

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
    var line_count: int = button.text.split("\n").size()
    var text_height: float = button.get_theme_font("font").get_height(button.get_theme_font_size("font_size")) * float(line_count) + float(button.get_theme_constant("line_spacing") * maxi(0,line_count-1))
    _expect(text_height <= button.size.y-style.get_minimum_size().y+0.5,"%s card '%s' hides text vertically" % [profile,button.text])

func _all_production_unit_text(hud: Node,logical: Vector2i,safe: Rect2,profile: String) -> Array[Dictionary]:
    var evidence: Array[Dictionary] = []
    var producer_types: Dictionary = {
        UnitData.UnitType.VILLAGER:BuildingData.BuildingType.TOWN_CENTER,
        UnitData.UnitType.SCOUT:BuildingData.BuildingType.TOWN_CENTER,
        UnitData.UnitType.INFANTRY:BuildingData.BuildingType.BARRACKS,
        UnitData.UnitType.ARCHER:BuildingData.BuildingType.ARCHERY_RANGE,
        UnitData.UnitType.CAVALRY:BuildingData.BuildingType.STABLE,
        UnitData.UnitType.SIEGE:BuildingData.BuildingType.SIEGE_WORKSHOP,
    }
    var scroll: ScrollContainer = hud.get("command_scroll")
    for unit_type: int in UnitData.UNITS:
        var building := BuildingBase.new()
        building.building_type = producer_types[unit_type]
        building.player_owner = 0
        building.state = BuildingBase.State.ACTIVE
        var queue := ProductionQueue.new()
        building.add_child(queue)
        building.set_production_queue(queue)
        queue.auto_queue_unit_type = unit_type
        var pending: Array = []
        for index: int in ProductionQueue.MAX_QUEUE_SIZE:
            pending.append({"unit_type":unit_type,"name":UnitData.get_unit_name(unit_type),"is_training":false})
        var trainable: Array = [unit_type]
        if building.building_type == BuildingData.BuildingType.TOWN_CENTER:
            trainable = [UnitData.UnitType.VILLAGER,UnitData.UnitType.SCOUT]
        _publish_selection_change(hud)
        hud.call("show_building_selection",BuildingData.get_building_name(building.building_type),5000,5000,pending,trainable,building)
        await _settle(hud,logical,safe)
        var unit_profile: String = "%s %s max queue" % [profile,UnitData.get_unit_name(unit_type)]
        var recruit: Button = (hud.get("_train_buttons_container") as HBoxContainer).get_node("TrainButton_%d" % unit_type)
        _expect(recruit.text.contains(UnitData.get_unit_name(unit_type)) and recruit.icon != null and recruit.get_node("CommandIconBadge").text == str(ProductionQueue.MAX_QUEUE_SIZE),unit_profile+" recruitment loses maximum queue badge")
        for resource: String in ["food","wood","gold"]:
            var cost: int = int(UnitData.get_unit_cost(unit_type).get(resource,0))
            if cost > 0:
                _expect(recruit.text.contains("%d%s" % [cost,resource.left(1).to_upper()]),unit_profile+" recruitment loses "+resource+" cost")
        var role: String = "Recon" if unit_type == UnitData.UnitType.SCOUT else UnitData.get_unit_counter_description(unit_type)
        if not role.is_empty():
            _expect(recruit.accessibility_name.contains(role) and str(hud.call("_selection_information")).contains(role),unit_profile+" recruitment loses role")
        for button: Button in (hud.get("_train_buttons_container") as HBoxContainer).get_children():
            if button.visible and not button.is_queued_for_deletion():
                _expect(scroll.get_global_rect().encloses(button.get_global_rect()),unit_profile+" recruitment/Repeat clipped: "+String(button.name))
                _expect(button.size.x>=48.0 and button.size.y>=48.0,unit_profile+" recruitment target under48px")
                _button_text_fits(button,unit_profile)
        await _tap_control(hud,hud.get("_queue_navigation_button"))
        await _settle(hud,logical,safe)
        _expect(hud.call("get_secondary_surface_name") == "queue",unit_profile+" actual Queue tap does not disclose cancellation")
        var group: Button = (hud.get("queue_container") as HBoxContainer).get_node("QueueUnit_%d" % unit_type)
        _expect(group.text.contains(UnitData.get_unit_name(unit_type)) and group.text.contains("x%d" % ProductionQueue.MAX_QUEUE_SIZE),unit_profile+" queue group loses name/count")
        for button: Control in (hud.get("queue_container") as HBoxContainer).get_children():
            if button.visible and not button.is_queued_for_deletion() and button is Button:
                _expect(scroll.get_global_rect().encloses(button.get_global_rect()),unit_profile+" queue action clipped: "+String(button.name))
                _expect(button.size.x>=48.0 and button.size.y>=48.0,unit_profile+" queue target under48px")
                _button_text_fits(button as Button,unit_profile)
        evidence.append({"unit":UnitData.get_unit_name(unit_type),"recruit_text":recruit.text,"recruit_size":str(recruit.size),"queue_text":group.text,"queue_size":str(group.size),"queue_shelf":str(scroll.get_global_rect())})
        _publish_selection_change(hud)
        hud.call("clear_selection")
        building.free()
    return evidence

func _non_production_shelf_density(hud: Node,logical: Vector2i,safe: Rect2,profile: String) -> Array[Dictionary]:
    var evidence: Array[Dictionary] = []
    var panel: Control = hud.get("selection_panel")
    var scroll: ScrollContainer = hud.get("command_scroll")
    for context: String in ["worker","army","foundation"]:
        var context_profile: String = profile+" "+context+" shelf"
        var foundation: BuildingBase = null
        _publish_selection_change(hud)
        if context == "foundation":
            foundation = BuildingBase.new()
            foundation.building_type = BuildingData.BuildingType.HOUSE
            foundation.player_owner = 0
            foundation.state = BuildingBase.State.CONSTRUCTING
            hud.call("show_building_selection","House",10,1000,[],[],foundation)
        else:
            var unit_type: int = UnitData.UnitType.VILLAGER if context == "worker" else UnitData.UnitType.INFANTRY
            hud.call("show_unit_selection",UnitData.get_unit_name(unit_type),50,50,"Seeking Food" if context == "worker" else "Attacking",1,{"unit_type":unit_type})
            hud.call("configure_unit_commands",true,context == "army","Aggressive","smart")
        await _settle(hud,logical,safe)
        _expect(panel.size.y <= 72.5,context_profile+" grows above72px")
        _expect(safe.encloses(panel.get_global_rect()),context_profile+" is outside safe area")
        _expect(not panel.get_global_rect().intersects((hud.get("minimap_bg") as Control).get_global_rect()),context_profile+" overlaps minimap")
        await _selection_name_readable(hud,logical,safe,context_profile)
        _text_fits(hud.get("selection_details"),context_profile)
        _expect((hud.get("selection_name") as Label).get_theme_font_size("font_size") == 14 and (hud.get("selection_details") as Label).get_theme_font_size("font_size") == 11,context_profile+" changes info typography")
        var info_width: float = (hud.get("selection_info_column") as Control).custom_minimum_size.x
        _expect(info_width == 148.0 if context == "foundation" else (info_width >= 96.0 and info_width <= 120.0),context_profile+" information column width leaves intended range")
        if context == "foundation":
            _expect(not scroll.visible,context_profile+" retains an empty command viewport")
            _expect(panel.size.x <= 168.0,context_profile+" retains empty width")
            _expect((hud.get("_selection_back_button") as Button).visible,context_profile+" loses Back")
        else:
            var commands: HBoxContainer = hud.get("_unit_command_container")
            _expect(commands.get_child_count() == 4,context_profile+" loses an action")
            var last_action: Button = commands.get_child(commands.get_child_count()-1)
            # On the narrowest notched worker corridor Clear already needs a short
            # scroll. Every whole target must remain reachable at the final offset.
            for button: Button in commands.get_children():
                _expect(button.visible and button.icon != null and button.size.x >= 48.0 and button.size.y >= 48.0,context_profile+" shrinks/hides "+String(button.name))
                _button_text_fits(button,context_profile)
                if not scroll.get_global_rect().encloses(button.get_global_rect()):
                    scroll.scroll_horizontal = int(scroll.get_h_scroll_bar().max_value-scroll.get_h_scroll_bar().page)
                    await get_tree().process_frame
                    await get_tree().process_frame
                _expect(scroll.get_global_rect().encloses(button.get_global_rect()),context_profile+" cannot reach full "+String(button.name))
            var empty_tail: float = panel.get_global_rect().end.x-last_action.get_global_rect().end.x
            _expect(empty_tail >= 0.0 and empty_tail <= 12.0,context_profile+" leaves %.1fpx after Clear" % empty_tail)
            (hud.get("_unit_more_button") as Button).pressed.emit()
            await _settle(hud,logical,safe)
            var advanced: Control = hud.get("_advanced_command_panel")
            _expect(advanced.visible and safe.encloses(advanced.get_global_rect()),context_profile+" loses safe More controls")
            for button: Button in (hud.get("_advanced_command_container") as HBoxContainer).get_children():
                _expect(advanced.get_global_rect().encloses(button.get_global_rect()) and button.size.x >= 48.0 and button.size.y >= 48.0,context_profile+" clips advanced "+String(button.name))
                _button_text_fits(button,context_profile+" More")
            (hud.get("_unit_more_button") as Button).pressed.emit()
        evidence.append({"context":context,"shelf":str(panel.get_global_rect()),"info_width":(hud.get("selection_info_column") as Control).custom_minimum_size.x,"details":(hud.get("selection_details") as Label).text})
        _publish_selection_change(hud)
        hud.call("clear_selection")
        if foundation:
            foundation.free()
    return evidence

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
