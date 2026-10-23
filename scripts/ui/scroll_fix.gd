class_name ScrollFix
extends RefCounted
## Makes touch dragging work over list content, not only in the gaps.
##
## A `ScrollContainer` only scrolls a drag it receives. Rows, cards and panels
## inside it default to `MOUSE_FILTER_STOP`, so a drag that starts on a row is
## swallowed by that row and only empty gaps scroll — on a phone this feels like
## "scrolling does not work". Marking the content `PASS` lets the event reach the
## container while buttons keep receiving their own presses.
##
## Applied once per screen; dynamic lists (missions, cards, shop) are re-scanned
## when a child enters the container.

static func apply(root: Node) -> void:
	if root == null or not root.is_inside_tree():
		return
	for node: Node in root.find_children("*", "ScrollContainer", true, false):
		var scroll := node as ScrollContainer
		if scroll == null:
			continue
		_relax(scroll)
		if not scroll.has_meta("scroll_fix"):
			scroll.set_meta("scroll_fix", true)
			scroll.child_entered_tree.connect(
				func(_child: Node) -> void: ScrollFix.apply(scroll)
			)


## Lets drag events bubble from the content up to the ScrollContainer.
static func _relax(scroll: ScrollContainer) -> void:
	for child: Node in scroll.find_children("*", "Control", true, false):
		var control := child as Control
		if control == null:
			continue
		# Sliders and text fields own their drag, so leave them alone.
		if control is Range or control is LineEdit:
			continue
		if control.mouse_filter == Control.MOUSE_FILTER_STOP:
			control.mouse_filter = Control.MOUSE_FILTER_PASS
