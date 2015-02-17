# t <- head(stations)

# t <- head(trips)
# t$start_date <- as.character(t$start_date)
# t$end_date <- as.character(t$end_date)

# t <- tail(trAggS2S)

# t <- head(byStnMetric)

# t <- print(xtable(t, digits=5), include.rownames=FALSE, type='html')




#### analysis
j <- subset(trAggDF, (strt_statn==42&end_statn==106) | (strt_statn==106&end_statn==42))
j

k <- subset(trAggDF, (strt_statn==3&end_statn==6) | (strt_statn==6&end_statn==3))
k

i <- subset(byStnMetric, statn==42)
i






## remove the last three characters (e.g. turn "startLng" to "start")
removeLastNChars <- function(x, n) {
  x <- as.character(x)
  x <- substr(x, 0, nchar(x)-n)
  return(x)
}


## add start and end coordinates to trips df
addStartAndEndCoordToTripsDF <- function(tripsDF, stationsDF) {
  tripsDF$startLng <- stationsDF$lng[match(tripsDF$strt_statn, stationsDF$id)]
  tripsDF$startLat <- stationsDF$lat[match(tripsDF$strt_statn, stationsDF$id)]
  tripsDF$endLng <- stationsDF$lng[match(tripsDF$end_statn, stationsDF$id)]
  tripsDF$endLat <- stationsDF$lat[match(tripsDF$end_statn, stationsDF$id)]
  return(tripsDF)
}
trips <- addStartAndEndCoordToTripsDF(trips, stations)

## for each trip, generate coordinate df to plot lines (of the trips)
genCoordsDF <- function(tripsDF) {
  tripsDF <- tripsDF[ , c('hubway_id', 'strt_statn', 'end_statn', 'startLng', 'startLat', 'endLat', 'endLng')]
  
  idVars <- c('hubway_id', 'strt_statn', 'end_statn')
  dfLng <- melt(tripsDF, id.vars=idVars, measure.vars=c('startLng', 'endLng'), 
                variable.name='var', value.name='lng')
  dfLat <- melt(tripsDF, id.vars=idVars, measure.vars=c('startLat', 'endLat'), 
                variable.name='var', value.name='lat')
  
  dfLng$var <- removeLastNChars(dfLng$var, 3)
  dfLat$var <- removeLastNChars(dfLat$var, 3)  
  
  outputDF <- merge(dfLng, dfLat, by=c(idVars, 'var'))
  return(outputDF)
  
}
# basemap
# x <- genCoordsDF(trips)
# y <- x[3:4, ]
# basemap + 
#   geom_line(data=y, aes(x=lng, y=lat, group=hubway_id), color='red', size=2)


## plot trip lines (OLD IMPLEMENTATION USING FOR LOOP)
plotTripLines <- function(plot, trAggDF, alpha=0.2) {
  
  ## order the rows from smallest to largest counts
  trAggDF <- trAggDF[order(trAggDF$cnt), ]
  
  ## set a spectrum of colors and calculate max (for coloring lines)
  colors <- colorRampPalette(c("lightblue", "yellowgreen", "yellow", "orange", "red"))(n = 100)
  maxcnt <- max(trAggS2S$cnt)
  
  ## set initial and final range (for line width)
  initRange <- range(trAggDF$cnt)  # initial range
  finRange <- c(0.2, 1)  # final range

  n <- nrow(trAggDF)
  for (i in 1:n) {
    print(paste(i, 'out of', n))
    startLoc <- c(trAggDF$strtLng[i], trAggDF$strtLat[i])
    endLoc <- c(trAggDF$endLng[i], trAggDF$endLat[i])
    intermPts <- gcIntermediate(startLoc, endLoc, n=50, addStartEnd=TRUE)
    cnt <- trAggDF$cnt[i]
    
    ## pick color based on count
    color <- pickColor(cnt, maxcnt, colors)
    
    ## calculate line width based on count
    lw <- transformScale(cnt, initRange, finRange)
    
    plot <- plot + 
      geom_line(data=as.data.frame(intermPts), aes(x=lon, y=lat, group=1), color=color, size=lw, alpha=0.8)
  }
  
  return(plot)
}

