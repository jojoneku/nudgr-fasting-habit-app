//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <flutter_gemma/flutter_gemma_plugin.h>
#include <flutter_timezone/flutter_timezone_plugin_c_api.h>

void RegisterPlugins(flutter::PluginRegistry* registry) {
  FlutterGemmaPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("FlutterGemmaPlugin"));
  FlutterTimezonePluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("FlutterTimezonePluginCApi"));
}
