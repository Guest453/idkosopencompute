return function(app)
  local win=app.window{title="settings",width=48,height=15}
  while true do
    local theme=app.theme()
    win:reset()
    win:text(2,2,"appearance")
    win:text(2,4,"desktop background presets")
    win:button("dark",2,6,12,"midnight")
    win:button("blue",16,6,12,"blue")
    win:button("green",30,6,12,"green")
    win:text(2,10,"idk os 1.0")
    win:text(2,11,"press ctrl+q to exit the desktop")
    local name,_,id=app.pull()
    if name=="idk_button" then
      if id=="dark" then theme.desktop=0x111827
      elseif id=="blue" then theme.desktop=0x0f2942
      elseif id=="green" then theme.desktop=0x123524 end
    end
  end
end
