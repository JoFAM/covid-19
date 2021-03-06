require(tidyverse)
require(git2r)

temp = list.files(path = "data-rivm/casus-datasets/",pattern="*.csv", full.names = T) ## Pull names of all available datafiles
dat <- read.csv(last(temp), )%>%
  dplyr::filter(Agegroup != "<50" & Agegroup != "Unknown")

dat$week <- strftime(dat$Date_statistics, format = "%V")
dat$value <- 1

dat_tidy <- aggregate(dat$value, by = list(Leeftijd = dat$Agegroup, Week = dat$week), FUN = sum)
dat_tidy$Week <- as.numeric(dat_tidy$Week)
colnames(dat_tidy) <- c("Leeftijd","Week","Besmettingen")

dat_besmettingen_abs <- dat_tidy %>%
  spread(Week,value = Besmettingen)


perc <- dat_tidy %>% 
  group_by(Week) %>% mutate(value = round((Besmettingen/sum(Besmettingen))*100,2))

dat_tidy <- cbind(dat_tidy[,c("Leeftijd","Week")],as.numeric(perc$value))
colnames(dat_tidy) <- c("Leeftijd","Week","Besmettingen")

dat_besmettingen_perc <- dat_tidy %>%
  spread(Week,value = Besmettingen)

dat_leeftijd <- rbind(dat_besmettingen_abs,dat_besmettingen_perc)

dat_leeftijd$Type <- c("Aantal besmettingen")
dat_leeftijd[11:20,isoweek(Sys.Date())] <- c("Percentage")

dat_leeftijd <- dat_leeftijd %>%
  relocate(Type, .before = Leeftijd)

write.csv(dat_leeftijd, file = "data-dashboards/age-week.csv", row.names = F)

git.credentials <- read_lines("git_auth.txt")
git.auth <- cred_user_pass(git.credentials[1],git.credentials[2])

add(repo, path = "data-dashboards/age-week.csv")
commit(repo, all = T, paste0("Update data agegroups per week ",Sys.Date()))
push(repo, credentials = git.auth)


