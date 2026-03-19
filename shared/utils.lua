-- Calcula el bono basado en el valor anterior
CalculateBonus = function (previous)
    local points = math.floor(previous)
    if points == nil then
        return 0
    end
    return points
end

-- Calcula el angulo de un vehiculo
Angle = function (veh)
    if not veh then return false end
    local velocityX, velocityY, velocityZ = table.unpack(GetEntityVelocity(veh))
    local velocityMagnitude = math.sqrt(velocityX*velocityX + velocityY*velocityY)

    local rotationX, rotationY, rotationZ = table.unpack(GetEntityRotation(veh,0))
    local sineRotationZ, cosineRotationZ = -math.sin(math.rad(rotationZ)), math.cos(math.rad(rotationZ))

    if GetEntitySpeed(veh)* 3.6 < 30 or GetVehicleCurrentGear(veh) == 0 then return 0, velocityMagnitude end

    local cosX = (sineRotationZ*velocityX + cosineRotationZ*velocityY)/velocityMagnitude
    if cosX > 0.966 or cosX < 0 then return 0, velocityMagnitude end
    return math.deg(math.acos(cosX))*0.5, velocityMagnitude
end
