return function(app)
  local win=app.window{title="calendar",width=48,height=18}
  local year,month=2026,7
  local names={"january","february","march","april","may","june","july","august","september","october","november","december"}
  local function leap(y) return y%4==0 and (y%100~=0 or y%400==0) end
  local function days(y,m)
    if m==2 then return leap(y) and 29 or 28 end
    return ({31,28,31,30,31,30,31,31,30,31,30,31})[m]
  end
  local function weekday(y,m,d)
    if m<3 then m=m+12 y=y-1 end
    local k,j=y%100,math.floor(y/100)
    local h=(d+math.floor(13*(m+1)/5)+k+math.floor(k/4)+math.floor(j/4)+5*j)%7
    return (h+5)%7
  end
  local function move(delta)
    month=month+delta
    if month<1 then month,year=12,year-1 elseif month>12 then month,year=1,year+1 end
    year=math.max(1,math.min(9999,year))
  end
  while true do
    win:reset()
    win:button("previous",2,2,8,"< month")
    win:text(17,2,names[month].." "..year)
    win:button("next",38,2,8,"month >")
    win:fill(2,4,43,1,0xdfe8f0)
    win:text(3,4,"mo    tu    we    th    fr    sa    su",0x4f6376,0xdfe8f0)
    local first=weekday(year,month,1)
    for day=1,days(year,month) do
      local index=first+day-1
      local x=3+(index%7)*6
      local y=6+math.floor(index/7)
      win:text(x,y,string.format("%2d",day))
    end
    win:text(2,14,"calendar opens at july 2026; use month controls",0x617487)
    local name,_,id=app.pull()
    if name=="idk_button" then if id=="previous" then move(-1) elseif id=="next" then move(1) end end
  end
end
