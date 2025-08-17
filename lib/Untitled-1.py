def fun(str):
    global returnedFirstValue, returnedLastValue
    firstLetter = str[0]
    returnedFirstValue = firstLetter*2
    lastLetter = str[-1]
    returnedLastValue = lastLetter*2

str = input("Enter word: ")
fun(str)
print(f"Passed word: {str} and returned values: {returnedFirstValue}, {returnedLastValue}")
