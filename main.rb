require 'pp'
require 'google_drive'

session = GoogleDrive::Session.from_service_account_key("Client_Secret.json")
if session == nil then raise "Error! Session is nil. Possible error: authenication expired?" else puts "Got session" end

spreadsheet = session.spreadsheet_by_title("Project Jeepers")
if spreadsheet == nil then raise "Error! Spreadsheet is nil. Possible error: incorrect spreadsheet title" else puts "Got spreadsheet" end

worksheet = spreadsheet.worksheet_by_sheet_id("0")
if worksheet == nil then raise "Error! Worksheet is nil. Possible error: incorrect worksheet GID" else puts "Got worksheet" end

$target_point_distance_max = 25000 

$target_point_distance_min = 10000

$accuracy_cut_off = 0.90

$render_distance = 2000

def translateCoordinatesFromGame(coordinates)

    coordinates = coordinates.split(":")
    xyz_format = [coordinates[2].to_f, coordinates[3].to_f, coordinates[4].to_f]
    return xyz_format
end

def translateCoordinatesToGame(key, value)
    return "GPS:#{key}:#{value[0]}:#{value[1]}:#{value[2]}:#a4a8ba:"
end

def distance(coordinate1, coordinate2)
    return Math.sqrt((coordinate2[0] - coordinate1[0])**2 + (coordinate2[1] - coordinate1[1])**2 + (coordinate2[2] - coordinate1[2])**2) 
end

def greatestDistance (listOfCoordinates)
    #[[23335.5, -156422.54, 99278.4], [37445.86, -143377.19, 77488.77], [20959.13, -146647.21, 92441.13], [12004.57, -149690.46, 81712.45], [17661.16, -141851.87, 64616.27]]

    greatestDistance = 0
    #farthestTwoPoints = [[], []]

    for coordinate in listOfCoordinates do
        for other_coordinate in listOfCoordinates do
            #Compares the coordinates and finds out which is the farthest away
            if distance(coordinate, other_coordinate) > greatestDistance
                greatestDistance = distance(coordinate, other_coordinate)
                #farthestTwoPoints = [coordinate, other_coordinate]
            end
        end
    end

    return greatestDistance
end

def findVessel(knownCoordinates)
    derived_points = {}
    unique_points = 0

    #Creates possible points
    for knownCoordinate in knownCoordinates do

        #First we need the radius of the circle

        search_width = ($target_point_distance_max - $target_point_distance_min).to_f
        
        ##Because the view distance is only 2km, the script cuts the 3D circles into 2km wide slices

        #Don't need to check the 0-2000 because that searches 2km of unnecessary space
        ($target_point_distance_min + $render_distance..$target_point_distance_max).step($render_distance) do |major_circle_radius|

            ##This cuts the vertical axis circle into several 2km slices
            ((major_circle_radius * -1)..major_circle_radius).step($render_distance) do |relative_z|
                

                #using the pythagorean theorem, we can determine the horizontal_circle_radius
                horizontal_circle_radius = Math.sqrt(major_circle_radius**2 - relative_z**2)

                #Throws out any data that is on the tip of the circles (radius = 0)
                if horizontal_circle_radius == 0 then next end

                #Now that we have the Z coordinate and the radius of the horizontal circle radius

                #Next we need to turn a circle into a group of possible search points, spaced by render distance
                #To do that, we use (Arc Length = Radians * radius) to find an angle to later plug into the unit circle
                #Solve for Radians => Arc Length/radius = Radians

                radians_delta = $render_distance.to_f/horizontal_circle_radius #Sorry I really don't now what to call it
                
                #We use the 2000 m angle change across our 10000-25000 m radius circle to figure out how many test points we need
                #And because we are going to have a lot of overlap in our test data, I feel like it is ok to round
                #Using the Math module pi because we are working with really big distances
                circle_radians = 2 * Math::PI

                number_of_test_points = (circle_radians/radians_delta).round

                #Calculates the x, y coordinates based on the radians_delta and the horizontal_circle_radius (this is relative to the point position)
                number_of_test_points.times do |i|
                    test_radian_measure = i * radians_delta

                    #We use the test angles to create a triangle, x_y_circle_radius as hypotenuse and test_radian_measure as the angle, and then solve for x, y
                    #You have to add the current position of the gps coordinate

                    gps_point = [horizontal_circle_radius * Math.cos(test_radian_measure) + knownCoordinate[0], horizontal_circle_radius * Math.sin(test_radian_measure) + knownCoordinate[1], knownCoordinate[2] + relative_z]

                    #Add the point to the derived points hash
                    derived_points["Test Point " + unique_points.to_s] = gps_point

                    #Iterates over the unique points variable
                    unique_points = unique_points + 1
                end
            end
        end
    end

    #Cleans data for points within $target_point_distance_max and $target_point_distance_min
    for knownCoordinate in knownCoordinates do

        derived_points.each do |key, value|

            #if distance(value, $targetCoords) <= 3000
            #    puts "#{key}: #{distance(value, $targetCoords)}"
            #end

            #Puts into list if distance is too great or too small
            if distance(value, knownCoordinate) > $target_point_distance_max or distance(value, knownCoordinate) < $target_point_distance_min
                #puts "Removed #{key} because the distance (#{distance(value, knownCoordinate)}) was outside of boundries..."
                derived_points.delete(key)
            end 
        end        
    end
    
    return derived_points
end

coordinateRows = {}

#Grabs all the coordinates from the spreadsheet
for row_index in (2..worksheet.num_rows) do
    translatedCoordinates = translateCoordinatesFromGame(worksheet[row_index, 1])
    coordinateRows[row_index] = {coordinates: translatedCoordinates}
end

puts "========"
puts "Known points: #{coordinateRows}" 
puts "========"

#Groups coordinates into player areas
playerNum = 0

coordinateRows.each do |row|
    #Creates a empty list for every coordinate
    groupingOfKnownCoordinates = []

    #Grabs all the coordinates within the same area
    coordinateRows.each do |other_row|
        #If the points are with 50 km of each other (the largest possible distance) then add them to a list
        if distance(row[1][:coordinates], other_row[1][:coordinates]) <= ($target_point_distance_max * 2)
            #Groups the numbers into a list
            groupingOfKnownCoordinates.push(other_row[1][:coordinates])

            playerGrouping = "Player #{playerNum}"

            #Checks if the other row already has a group, if so, it adds the current row.
            if other_row[1][:grouping] != nil then playerGrouping = other_row[1][:grouping] end

            #Adds the grouping information to the row hash
            other_row[1][:grouping] = playerGrouping
            
            worksheet[other_row[0], 2] = playerGrouping

        end
    end

    #Skips if it incounters an error
    if greatestDistance(groupingOfKnownCoordinates).to_f > $target_point_distance_max * 2
        worksheet[row[0], 3] = ""
        worksheet[row[0], 4] = "Error"
        next
    end

    #It uses the points to trianglulate the position
    #
    #puts "Currently, #{row[1][:grouping]} have a #{searchPoints.length} points to search"
    accuracy = greatestDistance(groupingOfKnownCoordinates).to_f/($target_point_distance_max * 2)
    if accuracy > 0.90
        puts "Calculating search points"
        searchPoints = findVessel(groupingOfKnownCoordinates)
        
        list = ""

        searchPoints.each do |name, coordinate|
            list = list + "#{translateCoordinatesToGame(name, coordinate)} \n"
        end

        worksheet[row[0], 3] = "#{searchPoints.length} points"
        worksheet[row[0], 4] = "#{accuracy.round(3)}*"
        worksheet[row[0], 5] = list

    else #Doesn't calcutate search points if the area is too big
        worksheet[row[0], 3] = ""
        worksheet[row[0], 4] = "#{accuracy.round(3)}*"

    end
    
    playerNum = playerNum + 1

    worksheet.save
end


