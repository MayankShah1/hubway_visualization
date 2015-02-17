#### initial setup
getwd()
setwd('/Users/hawooksong/Desktop/hubway')
rm(list=setdiff(ls(), c('trips', 'stations', 'boston')))


#### load data
loadData <- function() {
  missingTypes <- c(NA, '', ' ')
  trips <<- read.csv('./data/hubway_trips_201107_201311.csv', na.strings=missingTypes, stringsAsFactors=FALSE)
  stations <<- read.csv('./data/hubway_stations_201107_201311.csv', na.strings=missingTypes, stringsAsFactors=FALSE)  
}

#### load libraries
usePackage <- function(p) {
  if (!is.element(p, installed.packages()[,1]))
    install.packages(p, dep = TRUE)
  require(p, character.only = TRUE)
}

loadLibraries <- function() {
  usePackage('maps')
  usePackage('ggmap')
  usePackage('ggplot2')
  usePackage('dplyr')
  usePackage('geosphere')
  usePackage('reshape2')
  usePackage('RColorBrewer')
}



#### casting data types
casteDataTypeForTripsDF <- function(tripsDF) {
  tripsDF$seq_id <- NULL
  tripsDF$status <- NULL
  tripsDF$start_date <- strptime(tripsDF$start_date, format='%m/%d/%Y %H:%M:%S')
  # tripsDF$strt_statn <- as.factor(tripsDF$strt_statn)
  tripsDF$end_date <- strptime(tripsDF$end_date, format='%m/%d/%Y %H:%M:%S')
  # tripsDF$end_statn <- as.factor(tripsDF$end_statn)
  tripsDF$bike_nr <- as.factor(tripsDF$bike_nr)
  tripsDF$subsc_type <- as.factor(tripsDF$subsc_type)
  # tripsDF$zip_code <- gsub("'", '', tripsDF$zip_code)
  tripsDF$zip_code <- NULL
  tripsDF$birth_date <- as.factor(tripsDF$birth_date)
  tripsDF$gender <- as.factor(tripsDF$gender)
  return(tripsDF)
}

casteDataTypeForStations <- function(stationsDF) {
  stationsDF$terminal <- as.factor(stationsDF$terminal)
  stationsDF$station <- as.factor(stationsDF$station)
  stationsDF$municipal <- as.factor(stationsDF$municipal)
  stationsDF$status <- as.factor(stationsDF$status)
  return(stationsDF)
}



#### remove rows with missing stations info
removeRowsMissStns <- function(tripsDF) {
  tripsDF <- subset(tripsDF, !is.na(strt_statn) & !is.na(end_statn))
  return(tripsDF)
}



#### exclude loop trips (where starting and end stations are the same)
excludeLoopTrips <- function(tripsDF) {
  tripsDF <- subset(tripsDF, strt_statn != end_statn)
  return(tripsDF)
}



#### aggregations
## aggregate trips from station to station
aggTripsS2S <- function(tripsDF) {
  tripsDF$start_date <- as.character(tripsDF$start_date)
  tripsDF$end_date <- as.character(tripsDF$end_date)
  
  grp <- group_by(tripsDF, strt_statn, end_statn)  # set up the grouping
  agg <- dplyr::summarize(grp, cnt=n())  #set up aggregation by groups
  agg <- arrange(agg, cnt)  # order the data
  agg <- collect(agg)  # grab the result
  agg <- as.data.frame(agg)

  return(agg)
}

## add longitude and latitude info for starting stations
addStartLocs <- function(df) {
  df$strtLng <- stations$lng[match(df$strt_statn, stations$id)]
  df$strtLat <- stations$lat[match(df$strt_statn, stations$id)]
  return(df)  
}

## add longitude and latitude info for ending stations
addEndLocs <- function(df) {
  df$endLng <- stations$lng[match(df$end_statn, stations$id)]
  df$endLat <- stations$lat[match(df$end_statn, stations$id)]
  return(df)
}

## add longitude and latitude information to start and end stations
addStartAndEndLocs <- function(trAggDF) {
  trAggDF <- addStartLocs(trAggDF)
  trAggDF <- addEndLocs(trAggDF)
  return(trAggDF)
}

## dplyr count method
dplyrCnt <- function(grp) {
  agg <- dplyr::summarize(grp, cnt=sum(cnt))  # aggregate
  agg <- arrange(agg, cnt)  # order
  agg <- collect(agg)
  agg <- as.data.frame(agg)
  return(agg)
}

## standardize column names for trip-counts-by-station dfs
stdTripCtnByStnDFColnames <- function(df) {
  colnames(df) <- tolower(colnames(df))
  colnames(df) <- gsub('^end(_)?|^strt(_)?|^start(_)?', '', colnames(df))
  return(df)
}

## add station locations
addStnLocs <- function(df) {
  df$lng <- stations$lng[match(df$statn, stations$id)]
  df$lat <- stations$lat[match(df$statn, stations$id)]
  return(df)
}

## aggregate number of incoming/outgoing trips by station id
aggTripCntByStn <- function(trAggDF) {

  ## incoming trip counts by station
  grp <- group_by(trAggDF, end_statn)
  incTripCntByStnDF <- dplyrCnt(grp)
  incTripCntByStnDF <- stdTripCtnByStnDFColnames(incTripCntByStnDF)
  colnames(incTripCntByStnDF)[2] <- 'inc_cnt'

  ## outgoing trip counts by station
  grp <- group_by(trAggDF, strt_statn)
  outTripCntByStnDF <- dplyrCnt(grp)
  outTripCntByStnDF <- stdTripCtnByStnDFColnames(outTripCntByStnDF)  
  colnames(outTripCntByStnDF)[2] <- 'out_cnt'
  
  ## combine the two dfs, order, and return
  outputDF <- merge(incTripCntByStnDF, outTripCntByStnDF, by='statn')
  outputDF$tot_cnt <- outputDF$inc_cnt + outputDF$out_cnt
  outputDF <- outputDF[order(outputDF$statn), ]
  return(outputDF)
}

## add incoming and outgoing trip percentages
addIncOutTripPercs <- function(byStnMetricDF) {
  byStnMetricDF$inc_perc <- round(byStnMetricDF$inc_cnt / byStnMetricDF$tot_cnt * 100, 2)
  byStnMetricDF$out_perc <- round(byStnMetricDF$out_cnt / byStnMetricDF$tot_cnt * 100, 2)
  return(byStnMetricDF)
}

## function that takes in station-to-station pairs and collapses directionality of trips
## e.g. stnID4-stnID120 trip and stnID120-stnID4 trip should be combined into one pair (either as stnID4-stnID120 or stnID120-stnID4)
collapseDirectionS2S <- function(trAggDF) {
  output <- trAggDF

  ## collapse directionality dimension
  output$strtLng <- output$strtLat <- output$endLng <- output$endLat <- NULL
  output[1:2] <- t(apply(output, 1, function(x) sort(x[1:2])))
  output <- aggregate(cnt ~ ., data=output, FUN=sum)  
  
  ## order the output df by strt_statn and end_statn
  output <- output[order(output$strt_statn, output$end_statn), ]

  ## add start and end locations
  output <- addStartAndEndLocs(output)
  return(output)
}

## aggregate number of trips by hour and day

## mean/median trip duration

#### mapping functions
## get Boston map
getBostonMap <- function(maptype='roadmap', zoom=12, color='bw') {
  longitude <- -71.075
  latitude <- 42.36
  lonlat <- c(longitude, latitude)
  maptype <- 'roadmap'
  # boston <- get_map(location="boston", zoom=12)
  boston <- get_map(location = lonlat, 
                    zoom=zoom, maptype=maptype, color=color) 
  boston <- ggmap(boston)
  return(boston)
}

## plot stations
plotStations <- function(plot) {
  plot <- plot + 
    geom_point(data=stations, aes(x=lng, y=lat))
  return(plot)
}

## melt trAggS2S df for ggplot plotting
meltTripAggDF <- function(trAggDF) {
  x <- melt(trAggDF, id.vars=c('strt_statn', 'end_statn', 'cnt'), measure.vars=c('strtLng', 'endLng'))
  x$variable <- gsub('Lng', '', x$variable)
  colnames(x)[colnames(x)=='value'] <- 'lng'

  y <- melt(trAggDF, id.vars=c('strt_statn', 'end_statn', 'cnt'), measure.vars=c('strtLat', 'endLat'))
  y$variable <- gsub('Lat', '', y$variable)
  colnames(y)[colnames(y)=='value'] <- 'lat'
  
  z <- merge(x, y, by=c('strt_statn', 'end_statn', 'cnt', 'variable'))
  return(z)
}

## transform scale
transformScale <- function(initVal, initVals, resVals) {
  initRng <- range(initVals)  # initial scale
  resRng <- range(resVals)  # resultant scale
  
  resVal <- diff(resRng) * initVal / diff(initRng) + resRng[1]  # resultant value
  return(resVal)
}
# initVal <- 5; initVals <- c(0, 10); resVals <- c(5, 7)
# transformScale(initVal, initVals, resVals)

## pick color
pickColor <- function(cnt, maxcnt, colors) {
  colIndex <- round((cnt / maxcnt) * length(colors))
  colIndex <- ifelse(colIndex==0, 1, colIndex)
  color <- colors[colIndex]
  return(color)
}

## calculate line width based on count
addLineWidthsBasedCnt <- function(df, lwRng) {
  rawRng <- range(df$cnt)
  df$lw <- round(transformScale(df$cnt, rawRng, lwRng), 4)
  return(df)
}

## calculate color
addColorsBasedCnt <- function(df, colors) {
  maxcnt <- max(df$cnt)
  df$color <- pickColor(df$cnt, maxcnt, colors)
  return(df)
}

## plot trip lines 
plotTripLines <- function(plot, trAggDF, lwRng=c(0.2, 1.5), alpha=0.4) {
  
  ## melt wide-format df to long-format
  trAggDF <- meltTripAggDF(trAggDF)

  ## order df
  trAggDF <- trAggDF[order(trAggDF$cnt), ]

  ## calculate color based on count
  colors <- colorRampPalette(c("lightblue", "yellowgreen", "yellow", "orange", "red"))(n = 60)
  trAggDF <- addColorsBasedCnt(trAggDF, colors)

  ## calculate line width between the given range based on count
  trAggDF <- addLineWidthsBasedCnt(trAggDF, lwRng)

  ## draw plot (no good; constant line width)
  plot <- plot + 
    geom_line(data=trAggDF, aes(x=lng, y=lat,
                                group=interaction(strt_statn, end_statn, cnt)), 
              alpha=alpha,
              color=trAggDF$color, size=trAggDF$lw)

  ## return
  return(plot)
}

## plot incoming trip lines for single or multiple stations
plotIncTripLines <- function(plot, trAggDF, endStnIDs='all') {
  if (endStnIDs[1] != 'all') {
    trAggDF <- subset(trAggDF, end_statn %in% endStnIDs) 
  }
  plot <- plotTripLines(plot, trAggDF)
  return(plot)  # return
}

## plot outgoing trip lines for single or multiple stations
plotOutTripLines <- function(plot, trAggDF, strtStnIDs='all') {
  if (strtStnIDs[1] != 'all') {
    trAggDF <- subset(trAggDF, strt_statn %in% strtStnIDs)    
  }
  plot <- plotTripLines(plot, trAggDF)
  return(plot)
}

## plot total trip
plotTotTripLines <- function(plot, ndTrAggDF, stnIDs='all') {
  if (stnIDs[1] != 'all') {
    ndTrAggDF <- subset(ndTrAggDF, strt_statn %in% stnIDs | end_statn %in% stnIDs)    
  }
  plot <- plotTripLines(plot, ndTrAggDF)
  return(plot)
}

## create brackets (base 10)
createIntervalsBase10 <- function(values) {
  maxVal <- max(values)
  digits <- nchar(as.character(floor(maxVal)))
  maxCap <- round(maxVal, -(digits-1))
  interval <- 10 ^ (digits - 1)
  intervals <- seq(from=0, to=maxCap, by=interval)
  return(intervals)
}
# if maxVal is 3700, then creates intervals 0, 1000, 2000, 3000, 4000.
# if maxVal is 370, then create intervals 0, 100, 200, 300, 400
# if maxVal is 37, then create intervals 0, 10, 20, 30, 40
# if maxVal is 3.7, then create intervals 0, 1, 2, 3, 4
# if maxVal is 1007, 

## create brackets (base 5)
createIntervalsBase5 <- function(values) {
  maxVal <- max(values)
  digits <- nchar(as.character(floor(maxVal)))
  maxCap <- round(maxVal, -(digits-1))
  interval <- 10 ^ (digits - 1) / 2
  intervals <- seq(from=0, to=maxCap, by=interval)
  return(intervals)
}

## plot bubble chart for multiple stations
plotBubbleChart <- function(byStnMetricDF, stnIDs='all', type) {

  ## select stations 
  if (stnIDs != 'all') {
    byStnMetricDF <- subset(byStnMetricDF, statn %in% stnIDs) 
  }

  ## select type (incoming/outgoing/total count or incoming/outgoing trip percentage)
  byStnMetricDF <- melt(byStnMetricDF, id.vars=c('statn', 'lng', 'lat'), measure.vars=c('inc_cnt', 'out_cnt', 'tot_cnt', 'inc_perc', 'out_perc'))

  ## select variable
  byStnMetricDF <- subset(byStnMetricDF, variable==type)

  ## create count brackets
  maxDigits <- nchar(as.character(max(byStnMetricDF$value)))
  intervals <- createIntervalsBase5(byStnMetricDF$value)
  byStnMetricDF$bracket <- cut(byStnMetricDF$value, breaks=intervals, right=FALSE, include.lowest=TRUE, dig.lab=maxDigits)

  ## create colors
  nBrackets <- length(unique(byStnMetricDF$bracket))
  colors <- colorRampPalette(c("lightblue", "yellowgreen", "yellow", "orange", "red"))(n = nBrackets)

  ## plot
  plot <- plotStations(boston) + 
    geom_point(data=byStnMetricDF, aes(x=lng, y=lat, size=value, color=bracket, order=value), alpha=0.55) + 
    scale_size_continuous(range=c(5, 15)) + 
    scale_color_manual(values=colors)

  ## return plot
  return(plot)
}




#### program execution
## loading
loadLibraries()
loadData()

## preprocessing
stations <- casteDataTypeForStations(stations)
trips <- casteDataTypeForTripsDF(trips)
#trips <- excludeLoopTrips(trips)
trips <- removeRowsMissStns(trips)

## aggregating
trAggS2S <- aggTripsS2S(trips)
trAggS2S <- addStartAndEndLocs(trAggS2S)
ndTrAggS2S <- collapseDirectionS2S(trAggS2S)
byStnMetric <- aggTripCntByStn(trAggS2S)
byStnMetric <- addIncOutTripPercs(byStnMetric)
byStnMetric <- addStnLocs(byStnMetric)

## plotting base
boston <- getBostonMap()
plotStations(boston)

## plotting trip lines
# strtStnIDs <- endStnIDs <- stnIDs <- c(3, 22, 27, 40, 53)
# x <- plotIncTripLines(boston, trAggS2S, endStnIDs)
# plotStations(x)
# 
# y <- plotOutTripLines(boston, trAggS2S, strtStnIDs)
# plotStations(y)
# 
# z <- plotTotTripLines(boston, ndTrAggS2S, stnIDs)
# plotStations(z)
#
# t <- plotTotTripLines(boston, ndTrAggS2S, 'all')
# plotStations(t)
# dev.copy(png, './images/total_trip_lines.png')
# dev.off()

## plotting bubbles
# a <- plotBubbleChart(byStnMetric, 'all', 'tot_cnt')
# a
# dev.copy(png, './images/stns_by_tot_cnt.png')
# dev.off()
# 
# b <- plotBubbleChart(byStnMetric, 'all', 'inc_cnt')
# b
# dev.copy(png, './images/stns_by_inc_cnt.png')
# dev.off()
# 
# c <- plotBubbleChart(byStnMetric, 'all', 'out_cnt')
# c
# dev.copy(png, './images/stns_by_out_cnt.png')
# dev.off()
# 
# d <- plotBubbleChart(byStnMetric, 'all', 'inc_perc')
# d
# dev.copy(png, './images/stns_by_inc_perc.png')
# dev.off()
# 
# e <- plotBubbleChart(byStnMetric, 'all', 'out_perc')
# e
# dev.copy(png, './images/stns_by_out_perc.png')
# dev.off()
