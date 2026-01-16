# Icon mapping from class names to icon files
# Based on C:\Program Files\Tecnomatix_2301.0\eMPower\InitData\DefaultCust\*.bmp

function Get-IconForClass {
    param([string]$ClassName, [string]$Caption)
    
    # Remove "class " prefix if present
    $className = $ClassName -replace '^class\s+', ''
    
    # Direct class name mappings (from defaultCust.ppc and icon files)
    $iconMap = @{
        # Assembly
        'AssemblyPlaceholder' = 'AssemblyPlaceholder.bmp'
        'IntermediateAssembly' = 'IntermediateAssembly.bmp'
        'ProcessAssembly' = 'ProcessAssembly.bmp'
        
        # Resources
        'Plant' = 'Plant.bmp'
        'Zone' = 'Zone.bmp'
        'Line' = 'Line.bmp'
        'Station' = 'Station.bmp'
        'Cell' = 'Cell.bmp'
        'PrPlant' = 'PrPlant.bmp'
        'PrZone' = 'PrZone.bmp'
        'PrLine' = 'PrLine.bmp'
        'PrStation' = 'PrStation.bmp'
        
        # Processes
        'PrPlantProcess' = 'PrPlantProcess.bmp'
        'PrZoneProcess' = 'PrZoneProcess.bmp'
        'PrLineProcess' = 'PrLineProcess.bmp'
        'PrStationProcess' = 'PrStationProcess.bmp'
        
        # Tools/Devices
        'Clamp' = 'Clamp.bmp'
        'Container' = 'Container.bmp'
        'Conveyer' = 'Conveyer.bmp'
        'Device' = 'Device.bmp'
        'Dock_System' = 'Dock_System.bmp'
        'Fixture' = 'Fixture.bmp'
        'Flange' = 'Flange.bmp'
        'Gripper' = 'Gripper.bmp'
        'Gun' = 'Gun.bmp'
        'Human' = 'Human.bmp'
        'Robot' = 'Robot.bmp'
        'Turn_Table' = 'Turn_Table.bmp'
        'Work_Table' = 'Work_Table.bmp'
        
        # Parts
        'IntermediatePart' = 'IntermediatePart.bmp'
        
        # Other
        'Task' = 'Task.bmp'
        'PLCProgram' = 'PLCProgram.bmp'
        'SweptVolume' = 'SweptVolume.bmp'
        'desource' = 'desource.bmp'
        
        # Libraries
        'filter_library' = 'filter_library.bmp'
        'set_library' = 'set_library.bmp'
        'set_library_1' = 'set_library_1.bmp'
        'set_1' = 'set_1.bmp'
    }
    
    # Check direct mapping
    if ($iconMap.ContainsKey($className)) {
        return $iconMap[$className]
    }
    
    # Check if it's a Pm* class and try to map to base type
    if ($className -match '^Pm') {
        $baseType = $className -replace '^Pm', ''
        
        # Map common Pm* classes to icons
        $pmMap = @{
            'CompoundResource' = 'Cell.bmp'
            'Resource' = 'Device.bmp'
            'ToolPrototype' = 'Device.bmp'
            'CompoundPart' = 'IntermediatePart.bmp'
            'PartPrototype' = 'IntermediatePart.bmp'
            'CompoundAssembly' = 'IntermediateAssembly.bmp'
            'Assembly' = 'AssemblyPlaceholder.bmp'
            'Process' = 'PrLineProcess.bmp'
            'ProcessResource' = 'PrLine.bmp'
            'Operation' = 'Task.bmp'
            'Study' = 'Task.bmp'
            'LocationalStudy' = 'Task.bmp'
            'MfgLibrary' = 'filter_library.bmp'
            'ResourceLibrary' = 'filter_library.bmp'
            'RobcadResourceLibrary' = 'set_library.bmp'
            'PartLibrary' = 'filter_library.bmp'
            'OperationLibrary' = 'filter_library.bmp'
        }
        
        if ($pmMap.ContainsKey($baseType)) {
            return $pmMap[$baseType]
        }
    }
    
    # Try to match CAPTION_S_ to icon name (case-insensitive)
    if ($Caption) {
        $captionClean = $Caption -replace '[^a-zA-Z0-9_]', ''
        $iconPath = "C:\Program Files\Tecnomatix_2301.0\eMPower\InitData\DefaultCust\${captionClean}.bmp"
        if (Test-Path $iconPath) {
            return "${captionClean}.bmp"
        }
    }
    
    # Default icon based on common patterns
    if ($Caption) {
        $captionLower = $Caption.ToLower()
        if ($captionLower -match 'study|folder') {
            return 'filter_library.bmp'
        } elseif ($captionLower -match 'plant|factory') {
            return 'Plant.bmp'
        } elseif ($captionLower -match 'line') {
            return 'Line.bmp'
        } elseif ($captionLower -match 'station') {
            return 'Station.bmp'
        } elseif ($captionLower -match 'cell') {
            return 'Cell.bmp'
        } elseif ($captionLower -match 'zone') {
            return 'Zone.bmp'
        }
    }
    
    # Ultimate default
    return 'Device.bmp'
}

# Export function
Export-ModuleMember -Function Get-IconForClass
