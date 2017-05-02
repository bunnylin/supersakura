@echo off
REM This builds a zip file of the game.
REM Compile publishable versions of the exes first.
REM Also update releasefiles.txt to add new files to the release.

7z a -mx9 sakubin.zip @releasefiles.txt
move /Y sakubin.zip \website\ssakura\
