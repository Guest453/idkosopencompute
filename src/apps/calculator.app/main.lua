return function(app)
  local win=app.window{title="calculator",width=34,height=18}
  local value,stored,operation,replace="0",nil,nil,false

  local function calculate()
    if not operation or not stored then return true end
    local current=tonumber(value) or 0
    local result
    if operation=="+" then result=stored+current
    elseif operation=="-" then result=stored-current
    elseif operation=="*" then result=stored*current
    elseif current==0 then app.notify("cannot divide by zero") return false
    else result=stored/current end
    value=string.format("%.10g",result)
    stored,operation,replace=nil,nil,true
    return true
  end

  local rows={{"7","8","9","/"},{"4","5","6","*"},{"1","2","3","-"},{"0",".","=","+"}}
  while true do
    win:reset()
    win:text(2,2,(operation and (tostring(stored).." "..operation) or ""))
    win:text(2,4,value)
    win:button("clear",2,6,8,"clear")
    win:button("back",11,6,8,"back")
    for row,buttons in ipairs(rows) do
      for column,id in ipairs(buttons) do
        win:button(id,2+(column-1)*8,7+row*2,6,id)
      end
    end

    local name,_,id=app.pull()
    if name=="idk_button" then
      if id:match("^%d$") then
        if replace or value=="0" then value=id replace=false else value=value..id end
      elseif id=="." then
        if replace then value="0" replace=false end
        if not value:find(".",1,true) then value=value.."." end
      elseif id=="back" then
        if replace then value="0" replace=false
        else value=value:sub(1,-2); if value=="" or value=="-" then value="0" end end
      elseif id=="clear" then value,stored,operation,replace="0",nil,nil,false
      elseif id=="=" then calculate()
      elseif id=="+" or id=="-" or id=="*" or id=="/" then
        if operation and not replace and not calculate() then
          stored,operation,replace=nil,nil,true
        else
          stored,operation,replace=tonumber(value) or 0,id,true
        end
      end
    end
  end
end
