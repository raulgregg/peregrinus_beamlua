os.date("%M:%S",(time-CustomTool2.NumberIn1)/comp:GetPrefs("Comp.FrameFormat.Rate")).."."..string.format("%03d",(time-CustomTool2.NumberIn1)%comp:GetPrefs("Comp.FrameFormat.Rate")*1000/comp:GetPrefs("Comp.FrameFormat.Rate"))


iif(CustomTool2.Setup8.Value=="1",7732,iif(CustomTool2.Setup8.Value=="2",7427,iif(CustomTool2.Setup8.Value=="3",7126,iif(CustomTool2.Setup8.Value=="4",6836,iif(CustomTool2.Setup8.Value=="5",6554,iif(CustomTool2.Setup8.Value=="6",6271,iif(CustomTool2.Setup8.Value=="7",5961,5664)))))))