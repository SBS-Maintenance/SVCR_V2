
Gui, add, text, w400 h400 hwndhtext, rec files here
gui, show


return








renametofiledate(f)
{
	SplitPath, f, outfilename, outdir, outextension, outnamenoext, outdrive
	FileGetTime, time_f, %f%, C
	FormatTime, time_str, %time_f%, yyyyMMdd_HHmmss
	newfilename := RegExReplace(outfilename, "20\d\d\d\d\d\d_\d\d\d\d\d\d_00\d\d\d", time_str)
	FileAppend, %outdir%\%newfilename%`r`n, *
	return outdir . "\" . newfilename
}


GuiDropFiles:

Loop, parse, A_GuiEvent, `n
{
	FileMove, %A_LoopField% , % renametofiledate(A_LoopField)
	GuiControl,, %htext%, %A_LoopField%
}

return


GuiClose:
ExitApp


