#### example 1
u <- data.frame(str_statn=c(42, 106, 3, 6, 4, 5), end_statn=c(106, 42, 6, 3, 14, 5), cnt=c(23, 7, 100, 102, 1, 2))
v <- data.frame(str_statn=c(42, 3, 4, 5), end_statn=c(106, 6, 14, 5), cnt=c(30, 202, 1, 2))

u[1:2] <- t(apply(u, 1, function(x) sort(x[1:2])))
aggregate(cnt ~., u, sum)  




#### example 2
u <- data.frame(str_statn=c(10, 1, 3), end_statn=c(1, 10, 1), cnt=c(23, 7, 10))
v <- data.frame(str_statn=c(1, 1), end_statn=c(3, 10), cnt=c(10, 30))

u[1:2] <- t(apply(u, 1, function(x) sort(x[1:2])))
aggregate(cnt ~., u, sum)  

