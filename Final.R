################################
# Create edx set, validation set
################################

# Note: this process could take a couple of minutes

if(!require(tidyverse)) install.packages("tidyverse", repos = "http://cran.us.r-project.org")
if(!require(caret)) install.packages("caret", repos = "http://cran.us.r-project.org")
if(!require(data.table)) install.packages("data.table", repos = "http://cran.us.r-project.org")
library(tidyverse)
library(caret)
library(data.table)
library(tibble)
library(pillar)
# MovieLens 10M dataset:
# https://grouplens.org/datasets/movielens/10m/
# http://files.grouplens.org/datasets/movielens/ml-10m.zip

dl <- tempfile()
download.file("http://files.grouplens.org/datasets/movielens/ml-10m.zip", dl)

ratings <- fread(text = gsub("::", "\t", readLines(unzip(dl, "ml-10M100K/ratings.dat"))),
                 col.names = c("userId", "movieId", "rating", "timestamp"))

movies <- str_split_fixed(readLines(unzip(dl, "ml-10M100K/movies.dat")), "\\::", 3)
colnames(movies) <- c("movieId", "title", "genres")
movies <- as.data.frame(movies) %>% mutate(movieId = as.numeric(levels(movieId))[movieId],
                                           title = as.character(title),
                                           genres = as.character(genres))

movielens <- left_join(ratings, movies, by = "movieId")

# Validation set will be 10% of MovieLens data
set.seed(1, sample.kind="Rounding")
# if using R 3.5 or earlier, use `set.seed(1)` instead
test_index <- createDataPartition(y = movielens$rating, times = 1, p = 0.1, list = FALSE)
edx <- movielens[-test_index,]
temp <- movielens[test_index,]

# Make sure userId and movieId in validation set are also in edx set
validation <- temp %>% 
  semi_join(edx, by = "movieId") %>%
  semi_join(edx, by = "userId") %>%
  semi_join(edx, by = "genres")

# Add rows removed from validation set back into edx set
removed <- anti_join(temp, validation)
edx <- rbind(edx, removed)
dim(edx)
head(edx)

#Define train and test sets
# Test set will be 10% of edx data
set.seed(1, sample.kind="Rounding")
# if using R 3.5 or earlier, use `set.seed(1)` instead
test_index <- createDataPartition(y = edx$rating, times = 1, p = 0.1, list = FALSE)
train <- movielens[-test_index,]
temp <- movielens[test_index,]

# Make sure userId, movieId and genres in test set are also in train set
test <- temp %>% 
  semi_join(train, by = "movieId") %>%
  semi_join(train, by = "userId") %>%
  semi_join(train, by = "genres")

# Add rows removed from validation set back into edx set
removed <- anti_join(temp, test)
train <- rbind(train, removed)

#define RMSE function
RMSE <- function(true_ratings, predicted_ratings){
  sqrt(mean((true_ratings - predicted_ratings)^2))
}


#define mean rating
mu_hat <- mean(train$rating)
mu_hat

#rmse using mean rating
naive_rmse <- RMSE(test$rating, mu_hat)
naive_rmse

#evaluating movie effect
mu <- mean(train$rating) 
movie_avgs <- train %>% 
  group_by(movieId) %>% 
  summarize(b_i = mean(rating - mu))

predicted_ratings <- mu + test %>% 
  left_join(movie_avgs, by='movieId') %>%
  pull(b_i)
#rmse movie effect
movie_effect_rmse<-RMSE(predicted_ratings, test$rating)
#evaluating users effect
user_avgs <- train %>% 
  group_by(userId) %>%
  summarize(b_u = mean(rating - mu))

predicted_ratings <- test %>%
  left_join(user_avgs, by='userId') %>%
  mutate(pred = mu + b_u) %>%
  pull(pred)
#rmse users effect
users_effect_rmse<-RMSE(predicted_ratings, test$rating)
#evaluating genre effect
genre_avgs <- train %>% 
  group_by(genres) %>%
  summarize(b_g = mean(rating - mu))

predicted_ratings <- test %>%
  left_join(genre_avgs, by='genres') %>%
  mutate(pred = mu + b_g) %>%
  pull(pred)
#rmse genre effect
genre_effect_rmse<-RMSE(predicted_ratings, test$rating)

#evaluating combined movie, user and genre effects
user_avgs <- train %>% 
  left_join(movie_avgs, by='movieId') %>%
  group_by(userId) %>%
  summarize(b_u = mean(rating - mu - b_i))

genre_avgs<-train %>%
  left_join(movie_avgs,by='movieId') %>%
  left_join(user_avgs,by='userId') %>%
  group_by(genres)%>%
  summarize(b_g=mean(rating-mu-b_i-b_u))

predicted_ratings <- test %>% 
  left_join(movie_avgs, by='movieId') %>%
  left_join(user_avgs, by='userId') %>%
  left_join(genre_avgs,by='genres') %>%
  mutate(pred = mu + b_i + b_u + b_g) %>%
  pull(pred)
#rmse combined
movie_users_genre_effect_rmse<-RMSE(predicted_ratings, test$rating)

#table of results
rmse_results <- tibble(method = c("Just the average","Movie effect","Users effect","Genre effect","Movie, users and genre effect"), RMSE = c(naive_rmse,movie_effect_rmse,users_effect_rmse,genre_effect_rmse,movie_users_genre_effect_rmse))

rmse_results

#REGULARIZATION
# define a cross-validation set for movies
set.seed(1, sample.kind="Rounding")

# if using R 3.5 or earlier, use `set.seed(1)` instead
test_index <- createDataPartition(y = train$rating, times = 1, p = 0.1, list = FALSE)
edx_1 <- train[-test_index,]
temp <- train[test_index,]

# Make sure userId and movieId in validation set are also in edx set
cross_validation <- temp %>% 
  semi_join(edx_1, by = "movieId") %>%
  semi_join(edx_1, by = "userId") %>%
  semi_join(edx_1, by = "genres")

# Add rows removed from validation set back into edx set
removed <- anti_join(temp, cross_validation)
edx_1 <- rbind(edx_1, removed)

#test values for lambda
lambdas <- seq(0, 10, 0.25)

mu <- mean(edx_1$rating)
just_the_sum <- edx_1 %>% 
  group_by(movieId) %>% 
  summarize(s = sum(rating - mu), n_i = n())

rmses <- sapply(lambdas, function(l){
  predicted_ratings <- cross_validation %>% 
    left_join(just_the_sum, by='movieId') %>% 
    mutate(b_i = s/(n_i+l)) %>%
    mutate(pred = mu + b_i) %>%
    pull(pred)
  return(RMSE(predicted_ratings, cross_validation$rating))
})
qplot(lambdas, rmses)  
lambdas[which.min(rmses)]

#now repeat for users


# cross-validation set 
set.seed(1, sample.kind="Rounding")

# if using R 3.5 or earlier, use `set.seed(1)` instead
test_index <- createDataPartition(y = train$rating, times = 1, p = 0.1, list = FALSE)
edx_1 <- train[-test_index,]
temp <- train[test_index,]

# Make sure userId and movieId in validation set are also in edx set
cross_validation <- temp %>% 
  semi_join(edx_1, by = "movieId") %>%
  semi_join(edx_1, by = "userId") %>%
  semi_join(edx_1, by ="genres")
# Add rows removed from validation set back into edx set
removed <- anti_join(temp, cross_validation)
edx_1 <- rbind(edx_1, removed)

lambdas <- seq(0, 10, 0.25)

mu <- mean(edx_1$rating)
just_the_sum <- edx_1 %>% 
  group_by(userId) %>% 
  summarize(s = sum(rating - mu), n_i = n())

rmses <- sapply(lambdas, function(l){
  predicted_ratings <- cross_validation %>% 
    left_join(just_the_sum, by='userId') %>% 
    mutate(b_u = s/(n_i+l)) %>%
    mutate(pred = mu + b_u) %>%
    pull(pred)
  return(RMSE(predicted_ratings, cross_validation$rating))
})
qplot(lambdas, rmses)  
lambdas[which.min(rmses)]


#now for genres
# cross-validation set 
set.seed(1, sample.kind="Rounding")
# if using R 3.5 or earlier, use `set.seed(1)` instead
test_index <- createDataPartition(y = train$rating, times = 1, p = 0.1, list = FALSE)
edx_1 <- train[-test_index,]
temp <- train[test_index,]

# Make sure userId and movieId in validation set are also in edx set
cross_validation <- temp %>% 
  semi_join(edx_1, by = "movieId") %>%
  semi_join(edx_1, by = "userId") %>%
  semi_join(edx_1, by="genres")

# Add rows removed from validation set back into edx set
removed <- anti_join(temp, cross_validation)
edx_1 <- rbind(edx_1, removed)

lambdas <- seq(0, 10, 0.25)

mu <- mean(edx_1$rating)
just_the_sum <- edx_1 %>% 
  group_by(genres) %>% 
  summarize(s = sum(rating - mu), n_i = n())

rmses <- sapply(lambdas, function(l){
  predicted_ratings <- cross_validation %>% 
    left_join(just_the_sum, by='genres') %>% 
    mutate(b_g = s/(n_i+l)) %>%
    mutate(pred = mu + b_g) %>%
    pull(pred)
  return(RMSE(predicted_ratings, cross_validation$rating))
})
qplot(lambdas, rmses)  
lambdas[which.min(rmses)]


#to select the best lambda values, perform k-fold cross-validation with k=5
#first for movie 
set.seed(1, sample.kind="Rounding")
k<-5

lambda_1<-replicate(k, {
  test_index <- createDataPartition(y = train$rating, times = 1, p = 0.1, list = FALSE)
  edx_1 <- train[-test_index,]
  temp <- train[test_index,]
  cross_validation <- temp %>% 
    semi_join(edx_1, by = "movieId") %>%
    semi_join(edx_1, by = "userId") %>%
    semi_join(edx_1, by="genres")
  removed <- anti_join(temp, cross_validation)
  edx_1 <- rbind(edx_1, removed)
  lambdas <- seq(0, 10, 0.25)
  mu <- mean(edx_1$rating)
  just_the_sum <- edx_1 %>% 
    group_by(movieId) %>% 
    summarize(s = sum(rating - mu), n_i = n())
  rmses <- sapply(lambdas, function(l){
    predicted_ratings <- cross_validation %>% 
      left_join(just_the_sum, by='movieId') %>% 
      mutate(b_i = s/(n_i+l)) %>%
      mutate(pred = mu + b_i) %>%
      pull(pred)
    return(RMSE(predicted_ratings, cross_validation$rating))
  })
  qplot(lambdas, rmses)  
  lambdas[which.min(rmses)]
})
l_1<-mean(lambda_1)
l_1

#now for users
# cross-validation set 
set.seed(1, sample.kind="Rounding")

# if using R 3.5 or earlier, use `set.seed(1)` instead

k<-5
lambda_2<-replicate(k, {
  test_index <- createDataPartition(y = train$rating, times = 1, p = 0.1, list = FALSE)
  edx_1 <- train[-test_index,]
  temp <- train[test_index,]
  cross_validation <- temp %>% 
    semi_join(edx_1, by = "movieId") %>%
    semi_join(edx_1, by = "userId") %>%
    semi_join(edx_1, by="genres")
  removed <- anti_join(temp, cross_validation)
  edx_1 <- rbind(edx_1, removed)
  lambdas <- seq(0, 10, 0.25)
  mu <- mean(edx_1$rating)
  just_the_sum <- edx_1 %>% 
    group_by(userId) %>% 
    summarize(s = sum(rating - mu), n_i = n())
  rmses <- sapply(lambdas, function(l){
    predicted_ratings <- cross_validation %>% 
      left_join(just_the_sum, by='userId') %>% 
      mutate(b_u = s/(n_i+l)) %>%
      mutate(pred = mu + b_u) %>%
      pull(pred)
    return(RMSE(predicted_ratings, cross_validation$rating))
  })
  lambdas[which.min(rmses)]
})

l_2<-mean(lambda_2)
l_2

#then for genres

# cross-validation set 
set.seed(1, sample.kind="Rounding")

# if using R 3.5 or earlier, use `set.seed(1)` instead

k<-5
lambda_3<-replicate(k, {
  test_index <- createDataPartition(y = train$rating, times = 1, p = 0.1, list = FALSE)
  edx_1 <- train[-test_index,]
  temp <- train[test_index,]
  cross_validation <- temp %>% 
    semi_join(edx_1, by = "movieId") %>%
    semi_join(edx_1, by = "userId") %>%
    semi_join(edx_1, by="genres")
  removed <- anti_join(temp, cross_validation)
  edx_1 <- rbind(edx_1, removed)
  lambdas <- seq(0, 10, 0.25)
  mu <- mean(edx_1$rating)
  just_the_sum <- edx_1 %>% 
    group_by(genres) %>% 
    summarize(s = sum(rating - mu), n_i = n())
  rmses <- sapply(lambdas, function(l){
    predicted_ratings <- cross_validation %>% 
      left_join(just_the_sum, by='genres') %>% 
      mutate(b_g = s/(n_i+l)) %>%
      mutate(pred = mu + b_g) %>%
      pull(pred)
    return(RMSE(predicted_ratings, cross_validation$rating))
  })
  lambdas[which.min(rmses)]
})

l_3<-mean(lambda_3)
l_3


#now do regularization with the values l_1, l_2, l_3

mu <- mean(train$rating)

b_i <- train %>% 
  group_by(movieId) %>%
  summarize(b_i = sum(rating - mu)/(n()+l_1))

b_u <- train %>% 
  left_join(b_i, by="movieId") %>%
  group_by(userId) %>%
  summarize(b_u = sum(rating - b_i - mu)/(n()+l_2))

b_g <- train %>%
  left_join(b_u, by="userId") %>%
  left_join(b_i, by="movieId")%>%
  group_by(genres) %>%
  summarize(b_g = sum(rating - b_i - b_u - mu)/(n()+l_3))


predicted_ratings <- 
  test %>% 
  left_join(b_i, by = "movieId") %>%
  left_join(b_u, by = "userId") %>%
  left_join(b_g, by="genres")%>%
  mutate(pred = mu + b_i + b_u+b_g) %>%
  pull(pred)

regularized_movie_user_genre_rmse<-RMSE(predicted_ratings, test$rating)

regularized_movie_user_genre_rmse

#write results

options(pillar.sigfig=5)

rmse_results <- tibble(method = c("Just the average","Movie effect","Users effect","Genre effect","Movie, users and genre effect", "Regularized"), RMSE = c(naive_rmse,movie_effect_rmse,users_effect_rmse,genre_effect_rmse,movie_users_genre_effect_rmse,regularized_movie_user_genre_rmse))

rmse_results

#now check the best RMSE with validation set

mu <- mean(edx$rating)

b_i <- edx %>% 
  group_by(movieId) %>%
  summarize(b_i = sum(rating - mu)/(n()+l_1))

b_u <- edx %>% 
  left_join(b_i, by="movieId") %>%
  group_by(userId) %>%
  summarize(b_u = sum(rating - b_i - mu)/(n()+l_2))

b_g <- edx %>%
  left_join(b_u, by="userId") %>%
  left_join(b_i, by="movieId")%>%
  group_by(genres) %>%
  summarize(b_g = sum(rating - b_i - b_u - mu)/(n()+l_3))


predicted_ratings <- 
  validation %>% 
  left_join(b_i, by = "movieId") %>%
  left_join(b_u, by = "userId") %>%
  left_join(b_g, by="genres")%>%
  mutate(pred = mu + b_i + b_u+b_g) %>%
  pull(pred)

regularized_movie_user_genre_rmse_check<-RMSE(predicted_ratings, validation$rating)

regularized_movie_user_genre_rmse_check


