library(readr)
library(keras)
library(dplyr)
library(purrr)

# Define flags --------------------------------------------------------------

FLAGS <- flags(
  flag_string("normalization", "minmax", "One of minmax, zscore"),
  flag_string("activation", "relu", "One of relu, selu, tanh, sigmoid"),
  flag_numeric("learning_rate", 0.001, "Optimizer Learning Rate"),
  flag_integer("hidden_size", 15, "The hidden layer size")
)

# Decide normalization based on the flag

normalization_minmax <- function(x, desc) {
  map2_dfc(x, desc, ~(.x - .y$min)/(.y$max - .y$min))
}

normalization_zscore <- function(x, desc) {
  map2_dfc(x, desc, ~(.x - .y$mean)/(.y$sd))
}

normalization <- switch(FLAGS$normalization,
                        minmax = normalization_minmax,
                        zscore = normalization_zscore
)


# Read and split data --------------------------------------------------------------

credit_card_csv <- get_file(
  "creditcard.csv",
  "https://s3.amazonaws.com/r-keras-models/keras-fraud-autoencoder/creditcard.csv"
)
destination_file <- file.path('./fraud_detection_autoencoder/',basename(credit_card_csv))

file.copy(credit_card_csv, destination_file)

unlink(credit_card_csv)

df <- read_csv(destination_file, col_types = list(Time = col_number()))

df_train <- df %>% filter(row_number(Time) <= 200000) %>% select(-Time)
df_test <- df %>% filter(row_number(Time) > 200000) %>% select(-Time)


# Normalization -----------------------------------------------------------

get_desc <- function(x) {
  map(x, ~list(
    min = min(.x),
    max = max(.x),
    mean = mean(.x),
    sd = sd(.x)
  ))
} 

desc <- df_train %>% 
  select(-Class) %>% 
  get_desc()

x_train <- df_train %>%
  select(-Class) %>%
  normalization(desc) %>%
  as.matrix()

x_test <- df_test %>%
  select(-Class) %>%
  normalization(desc) %>%
  as.matrix()

y_train <- df_train$Class
y_test <- df_test$Class


# Defining the model ------------------------------------------------------

library(keras)
model <- keras_model_sequential()
model %>%
  layer_dense(FLAGS$hidden_size, activation = FLAGS$activation, input_shape = ncol(x_train)) %>%
  layer_dense(FLAGS$hidden_size, activation = FLAGS$activation) %>%
  layer_dense(FLAGS$hidden_size, activation = FLAGS$activation) %>%
  layer_dense(ncol(x_train))

summary(model)

model %>% compile(
  optimizer = optimizer_adam(lr = FLAGS$learning_rate), 
  loss = 'mean_squared_error'
)


# Model training ----------------------------------------------------------

checkpoint <- callback_model_checkpoint(
  filepath = "model.hdf5", 
  save_best_only = TRUE, 
  period = 1,
  verbose = 1
)

early_stopping <- callback_early_stopping(patience = 5)

model %>% fit(
  x_train[y_train == 0,], x_train[y_train == 0,], 
  epochs = 5, 
  batch_size = 32,
  validation_data = list(x_test[y_test == 0,], x_test[y_test == 0,]), 
  callbacks = list(checkpoint, early_stopping)
)

loss <- evaluate(model, x = x_test[y_test == 0,], y = x_test[y_test == 0,])
loss



pred_train <- predict(model, x_train)
mse_train <- apply((x_train - pred_train)^2, 1, sum)

pred_test <- predict(model, x_test)
mse_test <- apply((x_test - pred_test)^2, 1, sum)

library(Metrics)
auc(y_train, mse_train)
auc(y_test, mse_test)






