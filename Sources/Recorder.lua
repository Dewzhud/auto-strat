
 local player = game:GetService("Players").LocalPlayer
		


local lib = loadstring(game:HttpGet("https://raw.githubusercontent.com/fatalxxx1/grind-client/main/sk1%3Deet"))()
local Legit = lib:CreateWindow("legit", UDim2.new(0, 200, 0, 150),"")
local Render = lib:CreateWindow("render", UDim2.new(0, 150, 0, 20),"")

_G = {
	ag = false,
    door = false,
    esp= false,
    hbe = false,
    slide = 4,
}

local AGT = Legit:CreateToggle({
    Name = "Auto Gen",
    StartingState = true,
    Callback = function(state) 
       _G.ag = state
       if _G.ag then
        task.spawn(function()

             while  _G.ag  do
                task.wait()
                local Gui = player.PlayerGui:FindFirstChild("Gen")
		
                if Gui then
						local eventPath = player.PlayerGui:FindFirstChild("Gen"):FindFirstChild("GeneratorMain"):FindFirstChild("Event")

                    wait(_G.slide)
		        local args = {	
    	            {
                     Wires = true,
                     Switches = true,
                     Lever = true
    	            }
	            }

                eventPath:FireServer(unpack(args))
               Gui:Destroy()
                end
            end  
        
        
        end)

       end
    end
})



AGT:CreateSlider({
    Name = "Active Time ",
    Min = 3,
    Max = 5,
    Default = 4,
    Callback = function(val)
        _G.slide = val
	
    end
})


local DBT = Legit:CreateToggle({
    Name = "door block",
    StartingState = true,
    Callback = function(state) 
       _G.door = state
       if _G.door then
        task.spawn(function()

            while  _G.door  do
                task.wait()
            
                for _, v in pairs(player.PlayerGui:GetChildren()) do
   
                if v:IsA("ScreenGui") and v.Name == "Dot" then
                local Box = v:WaitForChild("Container").Box
        
       
                Box.Size = UDim2.new(0, 2000, 0, 2000)
                end
                end
            end  
        
        
        end)

       end
    end
})

local GenChild = workspace.PLAYERS.KILLER

local Kesp = Render:CreateToggle({
    Name = "Killer Esp",
    StartingState = true,
    Callback = function(state) 
       _G.esp = state
       if _G.esp then
        task.spawn(function()

            while  _G.esp  do
                 task.wait()
               
			        for _, E in pairs(GenChild:GetChildren()) do
				        if E:IsA('Model') then
					        local hitbox = E:WaitForChild('Hitbox')
                            local HL = hitbox:FindFirstChildOfClass('Highlight')
                            
                            if  HL then 
								HL.Enabled = true
							continue end
							hitbox.Transparency = 0
						    local Stupid = Instance.new('Highlight',hitbox)
						    Stupid.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
				    
                        end
			        end
            end 
        end)

       end
    end
})

local HBET = Render:CreateToggle({
    Name = "HItbox etend",
	Animation = false,
    StartingState = true,
    Callback = function(state) 
       _G.hbe = state
       if _G.hbe then
        task.spawn(function()

            while  _G.hbe  do
               
			         task.wait()
               
			        for _, E in pairs(GenChild:GetChildren()) do
				        if E:IsA('Model') then
					        local hitbox = E:WaitForChild('Hitbox')
                            local HL = hitbox:FindFirstChildOfClass('Highlight')
                            
                            if  not hitbox  then 
							    continue 
                            -- else if hitbox.Size.X == 6.6 and hitbox.Size.Y == 10 and hitbox.Size.Z == 6.6 then
                            --     continue
                            end
                            HL.OutlineTransparency = 1
                            hitbox.Size = Vector3.new(6.6,10,6.6)
                        end
			        end
            end 
        end)

       end
    end
})
