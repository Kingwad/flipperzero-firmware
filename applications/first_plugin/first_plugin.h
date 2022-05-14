#pragma once
#include <furi.h>
#include <gui/gui.h>
#include <input/input.h>

class FirstPlugin {
public:
	FirstPlugin(); 
	int32_t Run(void* _args);
	
private:
	enum EventType {
		EventTypeTick,
		EventTypeKey
	};
	
	struct PluginEvent {
		EventType type;
		InputEvent input;
	};
	
	struct PluginState {
		int x = 50;
		int y = 30;
	};
	
	static void RenderCallback(Canvas* _canvas, void* _context);
	static void InputCallback(InputEvent* _event, void* _context);
	
	bool Init();
	void Cleanup();
	
	bool m_initialized;
	osMessageQueueId_t m_eventQueue;
	ValueMutex m_stateMutex;
	ViewPort* m_viewPort;
	Gui* m_gui;
};
