@echo off
REM ============================================================
REM  MessApp - build and install on the phone in one step
REM  Usage:  install.bat            (debug build, fast)
REM          install.bat release    (smaller, slower, no logs)
REM ============================================================

setlocal
cd /d "D:\AndriodFlutter\opencode\MessApp"

set "JAVA_HOME=C:\tools\jdk-17"
set "ANDROID_HOME=C:\Android\Sdk"
set "ANDROID_SDK_ROOT=C:\Android\Sdk"
set "PATH=C:\flutter\bin;C:\tools\jdk-17\bin;C:\Android\Sdk\platform-tools;%PATH%"

set "BUILD=debug"
if /i "%~1"=="release" set "BUILD=release"

echo.
echo === 1/4  Checking phone connection ===
adb start-server >nul 2>&1
adb devices
adb wait-for-device

echo.
echo === 2/4  Building %BUILD% APK ===
call flutter build apk --%BUILD%
if errorlevel 1 (
  echo.
  echo BUILD FAILED - see the error above.
  pause
  exit /b 1
)

if "%BUILD%"=="release" (set "APK=build\app\outputs\flutter-apk\app-release.apk") else (set "APK=build\app\outputs\flutter-apk\app-debug.apk")

echo.
echo === 3/4  Installing on the phone ===
adb install -r -d "%APK%"
if errorlevel 1 (
  echo.
  echo INSTALL FAILED. If it says a signature conflict, run:
  echo    adb uninstall com.messapp.messapp
  echo then run this script again.
  pause
  exit /b 1
)

echo.
echo === 4/4  Launching MessApp ===
adb shell monkey -p com.messapp.messapp -c android.intent.category.LAUNCHER 1 >nul 2>&1
adb shell am start -n com.messapp.messapp/.MainActivity >nul 2>&1

echo.
echo ============================================================
echo  DONE - MessApp is installed and open on your phone.
echo ============================================================
pause