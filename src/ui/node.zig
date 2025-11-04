const std = @import("std");
const main = @import("main");
const ListUnmanaged = main.ListUnmanaged;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const CircularBufferQueue = main.utils.CircularBufferQueue;

pub const UiContext = struct {
	_active: ?*UiNode = null,
	_selected: ListUnmanaged(*UiNode) = .{},

	_all: ListUnmanaged(*UiNode) = .{},
	_all_handles: std.AutoHashMapUnmanaged(UiHandle, *UiNode) = .{},


	_eventQueue: CircularBufferQueue(EventData),

	pub fn init(_: NeverFailingAllocator) *UiContext {}
	pub fn deinit(_: NeverFailingAllocator) void {}
	pub fn activate(_: *UiContext, _: *UiNode) void {}
	pub fn select(_: *UiContext, _: *UiNode) void {}
};

pub const UiHandle = enum (u16) {
	null,
	_,
};

pub const EventData = struct {
	typ: enum { bubbling, direct },
	data: UiNode.Event,
};


pub const UiNode = struct {

	_parent: ?*UiNode = null,
	_children: ListUnmanaged(*UiNode) = .{},

	_isDirty: bool = false,
	_visible: bool = false,
	_disabled: bool = false,

	_scale: f32 = 1.0,
	_padding: u32 = 0,
	_margin: u32 = 0,

	pub fn init(_: NeverFailingAllocator, _: *UiContext) *UiNode {
		@panic("Not implemented.");
	}

	/// Called to deallocate the node.
	/// No interactions with UI can be performed at this stage.
	pub fn deinit(_: *UiNode,  _: NeverFailingAllocator) void {
		@panic("Not implemented.");
	}

	/// Callback called when element is hovered.
	/// Element is hovered when mouse cursor is placed within its bounding box.
	/// Controller can't trigger hover event.
	pub fn onHover(_: *UiNode, _: *UiContext, _: *HoverEvent) void {}
	const HoverEvent = struct {
		mouseX: f32,
		mouseY: f32,
	};

	pub fn onUnHover(_: *UiNode, _: *UiContext, _: *UnHoverEvent) void {}
	const UnHoverEvent = struct {};

	/// Callback called when element is updated.
	/// Element is updated every frame.
	pub fn onUpdate(_: *UiNode, _: *UiContext, _: *UpdateEvent) void {}
	const UpdateEvent = struct {
		context: *UiContext,
		deltaTime: f32, // unit?
	};

	/// Callback called when element is clicked.
	/// Element can only be clicked with mouse. Any of the mouse buttons can be used to trigger click event.
	/// Click event is triggered only if press and release happened within bounding box of the button.
	pub fn onClick(_: *UiNode, _: *UiContext,  _: *ClickEvent) void {}
	const ClickEvent = struct {
		pressMouseX: f32,
		pressMouseY: f32,
		releaseMouseX: f32,
		releaseMouseY: f32,
		button: enum { left, middle, right },
	};

	/// Callback called when element is activated.
	/// Element can be activated both with controller and with mouse.
	/// Element is activated with controller when controller navigated to element in UI
	/// and "activate" button was pressed on it.
	pub fn onActivate(_: *UiNode, _: *UiContext, _: *ActivateEvent) void {}
	const ActivateEvent = struct {
		source: enum { mouse, controller },
		posX: f32,
		posY: f32,
	};

	/// Callback called when element is deactivated.
	/// Element is deactivated when different element is activated.
	/// Element can be artificially deactivated without activating other elements.
	pub fn onDeactivate(_: *UiNode, _: *DeactivateEvent) void {}
	const DeactivateEvent = struct {};

	/// Callback called when element is selected.
	/// Elements are selected when they are clicked with mouse or navigated to using controller.
	/// When controller is used, element doesn't have to be activated for it to become selected.
	/// When mouse is used, select event is triggered before activate event.
	pub fn onSelect(_: *UiNode, _: *UiContext, _: *SelectEvent) void {}
	const SelectEvent = struct {};

	/// Callback called when element is deselected.
	/// Element loses selection when different element is selected.
	pub fn onDeselectEvent(_: *UiNode, _: *UiContext, _: *SelectEvent) void {}
	const DeselectEvent = struct {};

	/// Triggered when scroll wheel is used on active element.
	pub fn onScroll(_: *UiNode, _: *ScrollEvent) void {}
	const ScrollEvent = struct{
		distance: f32,
	};

	const Event = union(enum) {
		hover: HoverEvent,
		update: UpdateEvent,
		click: ClickEvent,
		activate: ActivateEvent,
		deactivate: DeactivateEvent,
		scroll: ScrollEvent,
	};
};
