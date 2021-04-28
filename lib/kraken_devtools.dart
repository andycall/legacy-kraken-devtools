/*
 * Copyright (C) 2021-present Alibaba Inc. All rights reserved.
 * Author: Kraken Team.
 */

import 'dart:isolate';
import 'dart:ffi';

import 'bridge/from_native.dart';

import 'inspector/ui_inspector.dart';
import 'inspector/isolate_server.dart';
import 'package:kraken/kraken.dart';
import 'package:kraken/bridge.dart';

void spawnIsolateInspectorServer(ChromeDevToolsService devTool, KrakenController controller, { int port = INSPECTOR_DEFAULT_PORT, String address }) {
  ReceivePort serverIsolateReceivePort = ReceivePort();

  serverIsolateReceivePort.listen((data) {
    if (data is SendPort) {
      devTool._isolateServerPort = data;
      String bundleURL = controller.bundleURL ?? controller.bundlePath ?? '<EmbedBundle>';
      devTool._isolateServerPort.send(InspectorServerInit(controller.view.contextId, port, '0.0.0.0', bundleURL));
    } else if (data is InspectorFrontEndMessage) {
      devTool.uiInspector.messageRouter(data.id, data.module, data.method, data.params);
    } else if (data is InspectorServerStart) {
      devTool.uiInspector.onServerStart(port);
    } else if (data is InspectorPostTaskMessage) {
      dispatchUITask(controller.view.contextId, Pointer.fromAddress(data.context), Pointer.fromAddress(data.callback));
    }
  });

  Isolate.spawn(serverIsolateEntryPoint, serverIsolateReceivePort.sendPort).then((Isolate isolate) {
    devTool._isolateServerIsolate = isolate;
  });
}

class ChromeDevToolsService extends DevToolsService {
  /// Design prevDevTool for reload page,
  /// do not use it in any other place.
  /// More detail see [InspectPageModule.handleReloadPage].
  static ChromeDevToolsService prevDevTools;

  static Map<int, ChromeDevToolsService> _contextDevToolMap = Map();
  static ChromeDevToolsService getDevToolOfContextId(int contextId) {
    return _contextDevToolMap[contextId];
  }

  Isolate _isolateServerIsolate;
  SendPort _isolateServerPort;
  SendPort get isolateServerPort => _isolateServerPort;

  /// Used for debugger inspector.
  UIInspector _uiInspector;
  UIInspector get uiInspector => _uiInspector;

  KrakenController _controller;
  KrakenController get controller => _controller;

  @override
  void dispose(KrakenController controller) {
    _uiInspector?.dispose();
    _controller = null;
    _isolateServerPort = null;
    _isolateServerIsolate.kill();
    _contextDevToolMap.remove(controller.view.contextId);
  }

  @override
  void init(KrakenController controller) {
    _contextDevToolMap[controller.view.contextId] = this;
    _controller = controller;
    registerUIDartMethodsToCpp();
    spawnIsolateInspectorServer(this, controller);
    _uiInspector = UIInspector(this);
    controller.view.elementManager.debugDOMTreeChanged = uiInspector.onDOMTreeChanged;
  }

  @override
  void reload(KrakenController controller) {
    _controller = controller;
    controller.view.elementManager.debugDOMTreeChanged = _uiInspector.onDOMTreeChanged;
    _isolateServerPort.send(InspectorReload(_controller.view.contextId));
  }
}
