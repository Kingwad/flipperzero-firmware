#include "first_plugin.h"
//#include <stdlib.h>

FirstPlugin::FirstPlugin()
	: m_initialized(false),
	  m_eventQueue(nullptr),
	  m_stateMutex(),
	  m_viewPort(nullptr),
	  m_gui(nullptr) {
	m_eventQueue = osMessageQueueNew(8, sizeof(PluginEvent), nullptr);
	PluginState* pluginState = new PluginState();
	if (!init_mutex(&m_stateMutex, pluginState, sizeof(pluginState))) {
		FURI_LOG_E("First_plugin", "cannot create mutex\r\n");
		delete pluginState;
		pluginState = nullptr;
	} else {
		m_viewPort = view_port_alloc();
		view_port_draw_callback_set(m_viewPort, RenderCallback, &m_stateMutex);
		view_port_input_callback_set(m_viewPort, InputCallback, m_eventQueue);
		m_gui = static_cast<Gui*>(furi_record_open("gui"));
		gui_add_view_port(m_gui, m_viewPort, GuiLayerFullscreen);
		m_initialized = true;
	}
}

FirstPlugin::~FirstPlugin() {
	view_port_enabled_set(m_viewPort, false);
	gui_remove_view_port(m_gui, m_viewPort);
	furi_record_close("gui");
	m_gui = nullptr;
	view_port_free(m_viewPort);
	m_viewPort = nullptr;
	osMessageQueueDelete(m_eventQueue);
	m_eventQueue = nullptr;
	PluginState* pluginState = static_cast<PluginState*>(acquire_mutex_block(&m_stateMutex));
	release_mutex(&m_stateMutex, pluginState);
	delete_mutex(&m_stateMutex);
	if (pluginState) {
		delete pluginState;
		pluginState = nullptr;
	}
}

int32_t FirstPlugin::Run(void* _args) {
	if (!m_initialized) {
		return 255;
	}
	(void)(_args); //unused
	for(bool processing = true; processing;) {
		PluginEvent event;
		osStatus_t eventStatus = osMessageQueueGet(m_eventQueue, &event, nullptr, 100);
		PluginState* pluginState = static_cast<PluginState*>(acquire_mutex_block(&m_stateMutex));
		if (eventStatus == osOK) {
			if (event.type == EventTypeKey && (event.input.type == InputTypePress || event.input.type == InputTypeRepeat)) {
				switch (event.input.key) {
					case InputKeyUp:
						pluginState->y--;
						break;
					case InputKeyDown:
						pluginState->y++;
						break;
					case InputKeyRight:
						pluginState->x++;
						break;
					case InputKeyLeft:
						pluginState->x--;
						break;
					case InputKeyOk:
					case InputKeyBack:
						processing = false;
						break;
				}
			}
		} else if (eventStatus != osErrorTimeout) {
			FURI_LOG_D("First_plugin", "Run: osMessageQueue: unexpected error %d", eventStatus);
			processing = false;
		}
		view_port_update(m_viewPort);
		release_mutex(&m_stateMutex, pluginState);
	}
	return 0;
}


void FirstPlugin::RenderCallback(Canvas* _canvas, void* _stateMutex) {
	ValueMutex* stateMutex = static_cast<ValueMutex*>(_stateMutex);
	const PluginState* pluginState = static_cast<PluginState*>(acquire_mutex(stateMutex, 25));
	if (!pluginState) {
		FURI_LOG_D("First_plugin", "RenderCallback mutex timeout");
		return;
	}
	canvas_draw_frame(_canvas, 0, 0, 128, 64);
	canvas_set_font(_canvas, FontPrimary);
	canvas_draw_str_aligned(_canvas, pluginState->x, pluginState->y, AlignRight, AlignBottom, "Hello World");
	release_mutex(stateMutex, pluginState);
}

void FirstPlugin::InputCallback(InputEvent* _event, void* _eventQueue) {
	osMessageQueueId_t eventQueue = static_cast<osMessageQueueId_t>(_eventQueue);
	PluginEvent event;
	event.type = EventTypeKey;
	event.input = *_event;
	osStatus_t status = osMessageQueuePut(eventQueue, &event, 0, osWaitForever);
	if (!status == osOK) {
		FURI_LOG_D("First_plugin", "InputCallback bad %d", status);
	}
}
