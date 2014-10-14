require "#{File.dirname(__FILE__)}/OsLib_Schedules"

#load OpenStudio measure libraries
module OsLib_LightingAndEquipment

  include OsLib_Schedules

  # return min ans max from array
  def OsLib_LightingAndEquipment.getExteriorLightsValue(model)

    facility = model.getFacility
    starting_exterior_lights_power = 0
    starting_exterior_lights = facility.exteriorLights
    starting_exterior_lights.each do |starting_exterior_light|
      starting_exterior_light_multiplier = starting_exterior_light.multiplier
      starting_exterior_light_def = starting_exterior_light.exteriorLightsDefinition
      starting_exterior_light_base_power = starting_exterior_light_def.designLevel
      starting_exterior_lights_power += starting_exterior_light_base_power * starting_exterior_light_multiplier
    end

    result = {"exteriorLightingPower" => starting_exterior_lights_power, "exteriorLights" => starting_exterior_lights}
    return result

  end #end of OsLib_LightingAndEquipment.getExteriorLightsValue

  # return min ans max from array
  def OsLib_LightingAndEquipment.removeAllExteriorLights(model,runner)
    facility = model.getFacility
    lightsRemoved = false
    starting_exterior_lights = facility.exteriorLights
    starting_exterior_lights.each do |starting_exterior_light|
      runner.registerInfo("Removed exterior light named #{starting_exterior_light.name}.")
      starting_exterior_light.remove
      lightsRemoved = true
    end

    result = lightsRemoved
    return result

  end #end of OsLib_LightingAndEquipment.removeAllExteriorLights

  # return min ans max from array
  def OsLib_LightingAndEquipment.addExteriorLights(model,runner, options = {})

    # set defaults to use if user inputs not passed in
    defaults = {
        "name" => "Exterior Light",
        "power" => 0,
        "subCategory" => "Exterior Lighting",
        "controlOption" => "AstronomicalClock",
        "setbackStartTime" => 0,
        "setbackEndTime" => 0,
        "setbackFraction" => 0.25,
    }

    # merge user inputs with defaults
    options = defaults.merge(options)

    ext_lights_def = OpenStudio::Model::ExteriorLightsDefinition.new(model)
    ext_lights_def.setName("#{options["name"]} Definition")
    runner.registerInfo("Setting #{ext_lights_def.name} to a design power of #{options["power"]} Watts")
    ext_lights_def.setDesignLevel(options["power"])

    #creating schedule type limits for the exterior lights schedule
    ext_lights_sch_type_limits = OpenStudio::Model::ScheduleTypeLimits.new(model)
    ext_lights_sch_type_limits.setName("#{options["name"]} Fractional")
    ext_lights_sch_type_limits.setLowerLimitValue(0)
    ext_lights_sch_type_limits.setUpperLimitValue(1)
    ext_lights_sch_type_limits.setNumericType("Continuous")

    # prepare values for profile
    if options["setbackStartTime"] == 24
      profile = {options["setbackEndTime"] => options["setbackFraction"],24.0 => 1.0}
    elsif options["setbackStartTime"] == 0
      profile = {options["setbackEndTime"] => options["setbackFraction"],24.0 => 1.0}
    elsif options["setbackStartTime"] > options["setbackEndTime"]
      profile = {options["setbackEndTime"] => options["setbackFraction"],options["setbackStartTime"] => 1.0,24.0 => options["setbackFraction"]}
    else
      profile = {options["setbackStartTime"] => 1.0,options["setbackEndTime"] => options["setbackFraction"]}
    end

    # inputs
    createSimpleSchedule_inputs = {
        "name" => options["name"],
        "winterTimeValuePairs" => profile,
        "summerTimeValuePairs" => profile,
        "defaultTimeValuePairs" => profile,
    }

    # create a ruleset schedule with a basic profile
    ext_lights_sch = OsLib_Schedules.createSimpleSchedule(model, createSimpleSchedule_inputs)

    #creating exterior lights object
    ext_lights = OpenStudio::Model::ExteriorLights.new(ext_lights_def,ext_lights_sch)
    ext_lights.setName("#{options["power"]} w Exterior Light")
    ext_lights.setControlOption(options["controlOption"])
    ext_lights.setEndUseSubcategory(options["subCategory"])

    result = ext_lights
    return result

  end #end of OsLib_LightingAndEquipment.addExteriorLights

  # add daylight sensor
  def OsLib_LightingAndEquipment.addDaylightSensor(model,options = {})

    # set defaults to use if user inputs not passed in
    defaults = {
        "name" => nil,
        "space" => nil,
        "position" => nil,
        "phiRotationAroundZAxis" => nil,
        "illuminanceSetpoint" => nil,
        "lightingControlType" => "1", # 1 = Continuous
        "minInputPowerFractionContinuous" => nil,
        "minOutputPowerFractionContinuous" => nil,
        "numberOfSteppedControlSteps" => nil,
    }

    # merge user inputs with defaults
    options = defaults.merge(options)

    pri_light_sensor = OpenStudio::Model::DaylightingControl.new(model)
    if not options["name"].nil? then  pri_light_sensor.setName(options["name"]) end
    if not options["space"].nil? then  pri_light_sensor.setSpace(options["space"]) end
    if not options["position"].nil? then  pri_light_sensor.setPosition(options["position"]) end
    if not options["phiRotationAroundZAxis"].nil? then  pri_light_sensor.setPhiRotationAroundZAxis(options["phiRotationAroundZAxis"]) end
    if not options["illuminanceSetpoint"].nil? then  pri_light_sensor.setIlluminanceSetpoint(options["illuminanceSetpoint"]) end
    if not options["lightingControlType"].nil? then  pri_light_sensor.setLightingControlType(options["lightingControlType"]) end

    result = pri_light_sensor
    return result

  end #end of OsLib_LightingAndEquipment.addDaylightSensor

  # make hash of hard assigned schedules with lighting levels
  def OsLib_LightingAndEquipment.createHashOfInternalLoadWithHardAssignedSchedules(internalLoadArray)

    hardAssignedScheduleHash = {}
    internalLoadArray.each do |load|
      if not load.isScheduleDefaulted
        # add to schedule hash
        if not load.schedule.empty?
          if not hardAssignedScheduleHash[load.schedule.get]
            hardAssignedScheduleHash[load.schedule.get] = 1
          else
            hardAssignedScheduleHash[load.schedule.get] += 1 # this is to catch multiple objects instances using the same hard assigned schedule
          end
        end
      end
    end

    result = hardAssignedScheduleHash
    return result

  end #end of OsLib_LightingAndEquipment.createHashOfInternalLoadWithHardAssignedSchedules

  # get value per area for electric equipment loads in space array.
  def OsLib_LightingAndEquipment.getEpdForSpaceArray(spaceArray)

    floorArea = 0
    electricEquipmentPower = 0

    spaceArray.each do |space|
      floorArea += space.floorArea*space.multiplier
      electricEquipmentPower +=  space.electricEquipmentPower*space.multiplier
    end

    epd = electricEquipmentPower/floorArea

    result = epd
    return result

  end #end of OsLib_LightingAndEquipment.getEpdForSpaceArray

  # get value per area for electric equipment loads in space array.
  def OsLib_LightingAndEquipment.getLpdForSpaceArray(spaceArray)

    floorArea = 0
    lightingPower = 0

    spaceArray.each do |space|
      floorArea += space.floorArea*space.multiplier
      lightingPower +=  space.lightingPower*space.multiplier
    end

    lpd = lightingPower/floorArea

    result = lpd
    return result

  end #end of OsLib_LightingAndEquipment.getLpdForSpaceArray

end