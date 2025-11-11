import pandas as pd

df = pd.read_csv("C:\\Users\\O304312\\Downloads\\Transaction.csv")

dupes = df[df.duplicated()]
