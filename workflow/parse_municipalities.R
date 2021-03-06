require(tidyverse)
require(data.table)

# const.date <- as.Date('2020-09-10') ## Change when you want to see a specific date

# methods
convert_to_trafficlight <- function(rel_increase) {
  trafficlight <- 
    ifelse( rel_increase >= 50, "🛑",
    ifelse( rel_increase > 5,   "🟧",
    ifelse( rel_increase > 0,   "🟡",
                                "✅"
    )))
  return(trafficlight)
}

calc_growth_increase <- function(increase_7d, increase_14d){
  growth <- 
    ifelse( 
      increase_14d-increase_7d <= 0,
      increase_7d * 100,
      ((increase_7d / (increase_14d - increase_7d)) - 1 ) * 100
    )
  return(growth) 
}

increase_growth_to_arrows <- function(increase_growth) {
  arrows <- 
    ifelse( increase_growth > 100,   "⬆️⬆️",
    ifelse( increase_growth > 1,     "⬆️",
   #ifelse( increase_growth <= -100, "⬇️⬇️",
    ifelse( increase_growth < -1,    "⬇️",
                                     "-"
  )))#)
  return(arrows)
}

# Parse and cleanup data
temp = list.files(path = "data-rivm/municipal-datasets/",pattern="*.csv", full.names = T) ## Pull names of all available datafiles
dat <- read.csv(last(temp), fileEncoding = "UTF-8") ## Take last filename from the folder, load csv
dat$date <- as.Date(dat$Date_of_report) ## character into Date class
last_date <- as.Date(last(dat$Date_of_report))
if(!exists("const.date")){ 
  const.date <- last_date
}

rm(temp)

dat.unknown <- dat %>%
  filter(Municipality_code == "")  %>%
  group_by(date) %>%
  summarise(
    Municipality_name = 'Unknown',
    Municipality_code = '',
    Total_reported = sum(Total_reported),
    Hospital_admission = sum(Hospital_admission),
    Deceased = sum(Deceased),
    .groups = 'drop_last'
  )

dat.total <- dat %>%
  group_by(date) %>%
  summarise(
    Municipality_name = 'Netherlands',
    Municipality_code = '',
    Total_reported = sum(Total_reported),
    Hospital_admission = sum(Hospital_admission),
    Deceased = sum(Deceased),
    .groups = 'drop_last'
  )

dat <- dat %>%
  filter(Municipality_code != "") %>% # Filter observations without municipal name
  select(
      Municipality_name, 
      Municipality_code,
      date, 
      Total_reported,
      Hospital_admission,
      Deceased
  ) %>% 
  rbind(dat.total) %>%
  rbind(dat.unknown)

rm(dat.unknown, dat.total)

# dat$Municipality_name <- recode(dat$Municipality_name, 
#   "SÃºdwest-FryslÃ¢n" = "Súdwest-Fryslân", 
#   "Noardeast-FryslÃ¢n" = "Noardeast-Fryslân"
# )

dat.cases <- dat %>%
  select(
    Municipality_name, 
    Municipality_code,
    date, 
    Total_reported
  )

dat.hosp <- dat %>%
  select(
    Municipality_name, 
    Municipality_code,
    date, 
    Hospital_admission
  )

dat.deaths <- dat %>%
  select(
    Municipality_name, 
    Municipality_code,
    date, 
    Deceased
  )

# Reshape file into wide format -- columns will be dates which report total cases on date
dat.cases <- reshape(dat.cases, 
  direction="wide", 
  timevar="date",
  idvar=c("Municipality_name","Municipality_code"))

dat.hosp <- reshape(dat.hosp, 
  direction="wide",
  timevar="date",
  idvar=c("Municipality_name","Municipality_code"))

dat.deaths <- reshape(dat.deaths, 
  direction="wide",
  timevar="date",
  idvar=c("Municipality_name","Municipality_code"))

date_diff <- ncol(dat.cases)-grep(paste("Total_reported.",const.date, sep=''), colnames(dat.cases))

# Add population
dat.pop <- read.csv("misc/municipalities-population.csv",
                    encoding = "UTF-8") %>%
  select(Municipality_code, population)

dat.cases <- merge(dat.pop, dat.cases, by = "Municipality_code", all.y=TRUE)
dat.cases[dat.cases$Municipality_name=="Netherlands", "population"] <- 17443797
write.csv(dat.cases, file = "data/municipality-totals.csv",
          fileEncoding = "UTF-8")

dat.hosp <- merge(dat.pop, dat.hosp, by = "Municipality_code", all.y=TRUE)
dat.hosp[dat.hosp$Municipality_name=="Netherlands", "population"] <- 17443797
write.csv(dat.hosp, file = "data/municipality-hospitalisations.csv",
          fileEncoding = "UTF-8")

dat.deaths <- merge(dat.pop, dat.deaths, by = "Municipality_code", all.y=TRUE)
dat.deaths[dat.deaths$Municipality_name=="Netherlands", "population"] <- 17443797
write.csv(dat.deaths, file = "data/municipality-deaths.csv",
          fileEncoding = "UTF-8")

# Calculate zero point
dat.zeropoint <- dat %>%
  filter(date >= as.Date('2020-08-01')) %>%
  group_by(Municipality_name)

dat.cases.lowest <- dat.zeropoint %>%
  slice(which.min(Total_reported)) %>%
  arrange(match(Municipality_name, c("Total", "Nederland")), Municipality_code)

dat.hosp.lowest <- dat.zeropoint %>%
  slice(which.min(Hospital_admission)) %>%
  arrange(match(Municipality_name, c("Total", "Nederland")), Municipality_code)

dat.deaths.lowest <- dat.zeropoint %>%
  slice(which.min(Deceased)) %>%
  arrange(match(Municipality_name, c("Total", "Nederland")), Municipality_code)

rm(dat.zeropoint)

# Parse today lists
dat.cases.today <-transmute(dat.cases,
  municipality = Municipality_name,
  Municipality_code = Municipality_code, 
  date = const.date,
  d0  = dat.cases[,ncol(dat.cases)-date_diff], # today
  d1  = dat.cases[,ncol(dat.cases)-date_diff-1], # yesterday
  d7  = dat.cases[,ncol(dat.cases)-date_diff-7], # last week
  d8  = dat.cases[,ncol(dat.cases)-date_diff-8], # yesterday's last week
  d14 = dat.cases[,ncol(dat.cases)-date_diff-14], # 2 weeks back
  aug1 = dat.cases$`Total_reported.2020-08-01`, # august 1st
  lowest_since_aug1 = dat.cases.lowest$`Total_reported`,
  lowest_since_aug1_date = dat.cases.lowest$`date`,
  current = d0-lowest_since_aug1,
  increase_1d = d0-d1, # Calculate increase since last day
  increase_7d = d0-d7, # Calculate increase in 7 days
  increase_14d = d0-d14, # Calculate increase in 14 days
  increase_growth = calc_growth_increase(increase_7d, increase_14d), # Compare growth of last 7 days vs 7 days before,
  growth = increase_growth_to_arrows(increase_growth),
  population,
  rel_increase_1d = increase_1d / population * 100000,
  rel_increase_7d = increase_7d / population * 100000,
  color = convert_to_trafficlight(rel_increase_7d),
  color_incl_new = ifelse(
      ((d1 - d8) <= 0 & (d0 - d1) > 0)
    | ((d0 - d7) <= 0 & (d0 - d1) > 0),  
  "💥", color),
  color_yesterday = convert_to_trafficlight( (d1 - d8)/ population * 100000),
  color_lastweek = convert_to_trafficlight( (d7 - d14)/ population * 100000)
)

dat.cases.today.simple <- dat.cases.today %>%
  filter(Municipality_code != "") %>%
  arrange(municipality) %>%
  select(
    current,
    color_incl_new,
    municipality,
    increase_1d,
    increase_7d,
    growth,
  )

dat.hosp.today <- transmute(dat.hosp,
  municipality = Municipality_name,
  Municipality_code = Municipality_code, 
  date = const.date,
  d0  = dat.hosp[,ncol(dat.hosp)-date_diff], # today
  d1  = dat.hosp[,ncol(dat.hosp)-date_diff-1], # yesterday
  d7  = dat.hosp[,ncol(dat.hosp)-date_diff-7], # last week
  d8  = dat.hosp[,ncol(dat.hosp)-date_diff-8], # yesterday's last week
  d14 = dat.hosp[,ncol(dat.hosp)-date_diff-14], # 2 weeks back
  aug1 = dat.hosp$`Total_reported.2020-08-01`, # august 1st
  lowest_since_aug1 = dat.hosp.lowest$`Hospital_admission`,
  lowest_since_aug1_date = dat.hosp.lowest$`date`,
  current = d0-lowest_since_aug1,
  increase_1d = d0-d1, # Calculate increase since last day
  increase_7d = d0-d7, # Calculate increase in 7 days
  increase_14d = d0-d14, # Calculate increase in 14 days
  increase_growth = calc_growth_increase(increase_7d, increase_14d), # Compare growth of last 7 days vs 7 days before,
  growth = increase_growth_to_arrows(increase_growth),
  population,
  rel_increase_1d = increase_1d / population * 100000,
  rel_increase_7d = increase_7d / population * 100000
)

dat.hosp.today.simple <- dat.hosp.today %>%
  filter(Municipality_code != "") %>%
  arrange(municipality) %>%
  select(
    current,
    municipality,
    increase_1d,
    increase_7d,
    growth,
  )

dat.deaths.today <- transmute(dat.deaths,
  municipality = Municipality_name,
  Municipality_code = Municipality_code, 
  date = const.date,
  d0 = dat.deaths[,ncol(dat.deaths)-date_diff], # today
  d1 = dat.deaths[,ncol(dat.deaths)-date_diff-1], # yesterday
  d7 = dat.deaths[,ncol(dat.deaths)-date_diff-7], # last week
  d8 = dat.deaths[,ncol(dat.deaths)-date_diff-8], # yesterday's last week
  d14 = dat.deaths[,ncol(dat.deaths)-date_diff-14], # 2 weeks back
  aug1 = dat.deaths$`Total_reported.2020-08-01`, # august 1st
  lowest_since_aug1 = dat.deaths.lowest$`Deceased`,
  lowest_since_aug1_date = dat.deaths.lowest$`date`,
  current = d0,
  increase_1d = d0-d1, # Calculate increase since last day
  increase_7d = d0-d7, # Calculate increase in 7 days
  increase_14d = d0-d14, # Calculate increase in 14 days
  increase_growth = calc_growth_increase(increase_7d, increase_14d), # Compare growth of last 7 days vs 7 days before,
  growth = increase_growth_to_arrows(increase_growth),
  population,
  rel_increase_1d = increase_1d / population * 100000,
  rel_increase_7d = increase_7d / population * 100000
)

dat.deaths.today.simple <- dat.deaths.today %>%
  filter(Municipality_code != "") %>%
  arrange(municipality) %>%
  select(
    current,
    municipality,
    increase_1d,
    increase_7d,
    growth,
  )


# Calculate totals
dat.cases.totals.growth <- dat.cases.today %>%
  filter(Municipality_code != "") %>%
  group_by(growth) %>%
  summarise(d0 = n(), .groups = 'drop_last') %>%
  arrange(match(growth, c("⬆️⬆️","⬆️","-","⬇️⬇️","⬇️")))
  
dat.cases.totals.color <- dat.cases.today %>%
  filter(Municipality_code != "") %>%
  group_by(color) %>%
  summarise(d0 = n(), .groups = 'drop_last')

dat.cases.totals.color_yesterday <- dat.cases.today %>%
  filter(Municipality_code != "") %>%
  group_by(color_yesterday) %>%
  summarise(d1 = n(), .groups = 'drop_last') %>%
  rename(color = color_yesterday)

dat.cases.totals.color_lastweek <- dat.cases.today %>%
  filter(Municipality_code != "") %>%
  group_by(color_lastweek) %>%
  summarise(d7 = n(), .groups = 'drop_last') %>%
  rename(color = color_lastweek)

dat.cases.totals.color <- dat.cases.totals.color %>%
  merge(dat.cases.totals.color_yesterday, by = "color", all.y=TRUE) %>%
  merge(dat.cases.totals.color_lastweek, by = "color", all.y=TRUE) %>%
  arrange(match(color, c("✅","🟡","🟧","🛑")))

rm(dat.cases.totals.color_yesterday, dat.cases.totals.color_lastweek)

dat.cases.totals.color <- mutate(dat.cases.totals.color,
  increase_1d = d0-d1, # Calculate increase since last day
  increase_7d = d0-d7, # Calculate increase in 7 days
)

# Write to csv
write.csv(dat.cases.today,        file = "data/municipality-today-detailed.csv",row.names = F, fileEncoding = "UTF-8")
write.csv(dat.cases.today.simple, file = "data/municipality-today.csv",row.names = F, fileEncoding = "UTF-8")
write.csv(dat.hosp.today,         file = "data/municipality-hospitalisations-today-detailed.csv",row.names = F, fileEncoding = "UTF-8")
write.csv(dat.hosp.today.simple,  file = "data/municipality-hospitalisations-today.csv",row.names = F, fileEncoding = "UTF-8")
write.csv(dat.deaths.today,       file = "data/municipality-deaths-today-detailed.csv",row.names = F, fileEncoding = "UTF-8")
write.csv(dat.deaths.today.simple,file = "data/municipality-deaths-today.csv",row.names = F, fileEncoding = "UTF-8")
write.csv(dat.cases.totals.growth,file = "data/municipality-totals-growth.csv",row.names = F, fileEncoding = "UTF-8")
write.csv(dat.cases.totals.color, file = "data/municipality-totals-color.csv",row.names = F, fileEncoding = "UTF-8")

rm(const.date)
rm(list=ls())

## Pull municipal data from CBS

#require(cbsodataR)
#require(geojsonio)

#dat.mun <- cbs_get_data("37230ned",add_column_labels = FALSE,Perioden = has_substring(c("2020MM06")))
#dat.mun <- dat.mun[,c("RegioS","BevolkingAanHetEindeVanDePeriode_15")]
#colnames(dat.mun) <- c("statcode","populatie")

#dat.mun <- dat.mun %>%
#  dplyr::filter(!is.na(populatie)) %>%
#  dplyr::filter(grepl("GM", statcode))

#gemeentegrenzen <- geojson_read("misc/maps/gemeentegrenzen2020.geojson", what = "sp")
#gemeentes <- gemeentegrenzen@data[,c(2,4)]

#gemeente.stats <- merge(gemeentes, dat.mun, by = "statcode")
#colnames(gemeente.stats) <- c("Municipality_code","Municipality_name","population")
#write.csv(gemeente.stats, file = "misc/municipalities-population.csv")



# Municipality data

#temp = list.files(path = "data-rivm/municipal-datasets/",pattern="*.csv", full.names = T)
#myfiles = lapply(temp, read.csv)

#temp = list.files(path = "data-rivm/municipal-datasets/",pattern="*.csv")

#myfiles <- mapply(cbind, myfiles, "name_dataset"=temp,SIMPLIFY = F)

#datefunction <- function(x) {
#  x[x$Date_of_report == last(x$Date_of_report),]
#} ## Function for cases per day

#res <- lapply(myfiles, datefunction)

#df <- map_dfr(res, ~{
#  .x
#})

#df$date <- as.Date(df$Date_of_report)

#df <- df %>%
#  filter(Municipality_name != "") %>%
#  select(Municipality_name, date, Total_reported)

#data_wide <- reshape(df, direction="wide",
#                     timevar="date",
#                     idvar="Municipality_name")

# Calc diffs

#col.start.diff <- ncol(data_wide)+1

#dates.lead <- names(data_wide)[3:ncol(data_wide)] ## Set lead colnames for diff
#dates.trail <- names(data_wide)[2:(ncol(data_wide)-1)] ## Set trail colnames for diff

# Calculate moving difference between cases per day
#data_wide[paste0("diff",seq_along(dates.lead)+1,seq_along(dates.trail))] <- data_wide[dates.lead] - data_wide[dates.trail]

#week <- last(colnames(data_wide), n = 7)

#data_wide$weeksum <- rowSums(data_wide[,week])


