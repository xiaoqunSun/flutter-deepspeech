import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:deepspeech/deepspeech.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _error= '';
  String _result = '';
  bool _speechStarted = false;
  int _modelIndex = 0;

  void _refreshResult(event)  {
    final Map<dynamic, dynamic> map = event;
    _result = map["ret"]; 
    
    setState(() {

    });
  }
  void _aActiveChanged() async {
      if (_speechStarted) {
        _speechStarted = false;
        await Deepspeech.stopSpeech(false);
      } else {
        _speechStarted = true;
        Deepspeech.startSpeech(_modelIndex,false,_refreshResult,print);
        _error = await Deepspeech.getLastError();
      }
    setState(() {

    });
  }

  @override
  void initState() {
    super.initState();
    initPlatformState();
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  Future<void> initPlatformState() async {

    int modelIndex = await Deepspeech.createModel("deepspeech-0.8.0-models.tflite");
    Deepspeech.setScorer(modelIndex, "today_is_different.scorer", 0, 0);
    String error = await Deepspeech.getLastError();
    
    // If the widget was removed from the tree while the asynchronous platform
    // message was in flight, we want to discard the reply rather than calling
    // setState to update our non-existent appearance.
    if (!mounted) return;
   
             
    setState(() {
      _error = error;
      _modelIndex = modelIndex;
    });
  }
  Widget buildRaisedButton(){
    //它默认带有阴影和灰色背景。按下后，阴影会变大
    return RaisedButton(
      child: Text(_speechStarted ? "StopSpeech":"StartSpeech"),
      onPressed: _aActiveChanged,
    );
  }
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body: Center(
          child: Column(
             mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.center,
          verticalDirection: VerticalDirection.down,

            children: <Widget>[
              Text('deepspeech error : $_error\n'),
              Text('Result : $_result\n'),
              buildRaisedButton(),
            ],
          )
        ),
      ),
    );
  }
}
