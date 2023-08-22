ffmpeg_decklink5 -f decklink -list_devices 1 -i dummy
ffmpeg_decklink5 -f decklink -list_formats 1 -i "DeckLink 8K Pro (1)"
ffmpeg2018 -f dshow -list_devices 1 -i dummy
pause

