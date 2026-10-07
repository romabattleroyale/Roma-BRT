extends CanvasLayer

func _ready() -> void:
    for action in ["move_forward","move_back","move_left","move_right"]:
        if not InputMap.has_action(action): InputMap.add_action(action)
    var panel := Control.new()
    panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(panel)
    _button(panel,"▲",Vector2(86,560),"move_forward")
    _button(panel,"▼",Vector2(86,650),"move_back")
    _button(panel,"◀",Vector2(8,650),"move_left")
    _button(panel,"▶",Vector2(164,650),"move_right")
    var hint := Label.new()
    hint.text = "Trascina a destra per ruotare 360°"
    hint.position = Vector2(870,650)
    hint.add_theme_font_size_override("font_size",20)
    panel.add_child(hint)

func _button(parent: Control, label_text: String, pos: Vector2, action: String) -> void:
    var b := Button.new()
    b.text = label_text
    b.position = pos
    b.size = Vector2(72,72)
    b.modulate = Color(1,1,1,0.82)
    b.add_theme_font_size_override("font_size",30)
    b.button_down.connect(func(): Input.action_press(action))
    b.button_up.connect(func(): Input.action_release(action))
    parent.add_child(b)
