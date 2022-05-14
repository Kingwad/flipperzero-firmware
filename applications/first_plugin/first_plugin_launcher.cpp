#include "first_plugin.h"

// app enter function
extern "C" int32_t first_plugin_app(void* _args) {
	FirstPlugin* app = new FirstPlugin();
	int32_t error = app->Run(_args);
	delete app;

	return error;
}
