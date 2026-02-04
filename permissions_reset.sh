#!/bin/bash

APP_ID="com.babylonfish.app"
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
open "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
tccutil reset Accessibility "$APP_ID" 2>/dev/null || true
tccutil reset ListenEvent "$APP_ID" 2>/dev/null || true
