import math
from random import gauss

mean = 2
var = 1
rand_nums = []
i = 0

while i < 1000:
    num = int(gauss(mean, math.sqrt(var)) * 10)
    if num < 0 or num > 100:
        continue
    rand_nums.append(num)
    i += 1

print(rand_nums)