"""
build_food_db.py — Generate assets/food_db.sqlite from curated USDA SR Legacy data.

Usage:
    python scripts/build_food_db.py

Output:
    assets/food_db.sqlite  (~1-2 MB, ready to bundle with Flutter app)

Data source: USDA FoodData Central — SR Legacy (public domain).
Values are per 100g unless noted. All calories are kcal.

To regenerate after adding foods, just re-run this script.
"""

import sqlite3
import os
import sys

# ---------------------------------------------------------------------------
# Curated food data: (id, name, category, cal, protein, carbs, fat)
# Values per 100g. Source: USDA FoodData Central SR Legacy (public domain).
# ---------------------------------------------------------------------------
FOODS = [
    # ── Poultry ─────────────────────────────────────────────────────────────
    ("1001", "Chicken Breast, Cooked",           "Poultry",     165, 31.0,  0.0,  3.6),
    ("1002", "Chicken Thigh, Cooked",            "Poultry",     209, 26.0,  0.0, 11.0),
    ("1003", "Chicken Drumstick, Cooked",        "Poultry",     172, 28.3,  0.0,  5.7),
    ("1004", "Chicken Wing, Cooked",             "Poultry",     290, 27.0,  0.0, 19.0),
    ("1005", "Turkey Breast, Roasted",           "Poultry",     135, 29.9,  0.0,  1.0),
    ("1006", "Ground Turkey, Cooked",            "Poultry",     218, 27.4,  0.0, 11.8),
    ("1007", "Chicken Liver, Cooked",            "Poultry",     167, 24.5,  0.9,  6.5),
    ("1008", "Duck Breast, Cooked",              "Poultry",     201, 28.2,  0.0,  9.7),

    # ── Beef ─────────────────────────────────────────────────────────────────
    ("2001", "Ground Beef 80/20, Cooked",        "Beef",        254, 26.1,  0.0, 17.0),
    ("2002", "Ground Beef Lean, Cooked",         "Beef",        218, 26.3,  0.0, 12.0),
    ("2003", "Beef Sirloin, Cooked",             "Beef",        207, 30.6,  0.0,  8.5),
    ("2004", "Beef Ribeye, Cooked",              "Beef",        291, 26.5,  0.0, 19.9),
    ("2005", "Beef Tenderloin, Cooked",          "Beef",        270, 28.0,  0.0, 17.0),
    ("2006", "Beef Brisket, Cooked",             "Beef",        274, 24.9,  0.0, 18.7),
    ("2007", "Beef Liver, Cooked",               "Beef",        175, 26.4,  4.4,  4.9),
    ("2008", "Beef Chuck Roast, Cooked",         "Beef",        265, 28.3,  0.0, 16.4),
    ("2009", "Beef Steak T-Bone, Cooked",        "Beef",        305, 26.0,  0.0, 21.7),
    ("2010", "Corned Beef, Cooked",              "Beef",        251, 18.2,  0.5, 19.2),

    # ── Pork ─────────────────────────────────────────────────────────────────
    ("3001", "Pork Chop, Cooked",                "Pork",        231, 29.4,  0.0, 12.5),
    ("3002", "Pork Tenderloin, Cooked",          "Pork",        166, 29.9,  0.0,  4.6),
    ("3003", "Ground Pork, Cooked",              "Pork",        297, 25.7,  0.0, 20.8),
    ("3004", "Bacon, Cooked",                    "Pork",        541, 37.0,  1.4, 42.0),
    ("3005", "Ham, Cooked",                      "Pork",        163, 21.6,  1.5,  7.7),
    ("3006", "Pork Belly, Cooked",               "Pork",        518, 9.3,   0.0, 53.0),
    ("3007", "Pork Ribs, Cooked",                "Pork",        285, 24.7,  0.0, 20.0),
    ("3008", "Italian Sausage, Cooked",          "Pork",        346, 19.1,  4.3, 28.2),
    ("3009", "Prosciutto",                       "Pork",        250, 25.9,  0.3, 16.0),

    # ── Lamb & Other Meats ────────────────────────────────────────────────────
    ("4001", "Lamb Chop, Cooked",                "Lamb",        294, 25.0,  0.0, 20.8),
    ("4002", "Lamb Ground, Cooked",              "Lamb",        283, 25.5,  0.0, 19.6),
    ("4003", "Veal, Cooked",                     "Lamb",        196, 30.1,  0.0,  7.8),
    ("4004", "Bison Ground, Cooked",             "Lamb",        218, 27.8,  0.0, 11.3),
    ("4005", "Venison, Cooked",                  "Lamb",        187, 30.2,  0.0,  6.4),

    # ── Fish & Seafood ─────────────────────────────────────────────────────
    ("5001", "Salmon, Atlantic, Cooked",         "Fish",        206, 20.4,  0.0, 13.4),
    ("5002", "Tuna, Canned in Water",            "Fish",        116, 25.5,  0.0,  0.8),
    ("5003", "Cod, Cooked",                      "Fish",         90, 19.4,  0.0,  0.7),
    ("5004", "Tilapia, Cooked",                  "Fish",        128, 26.2,  0.0,  2.7),
    ("5005", "Shrimp, Cooked",                   "Fish",         99, 20.9,  0.0,  1.1),
    ("5006", "Sardines, Canned in Oil",          "Fish",        208, 24.6,  0.0, 11.5),
    ("5007", "Mackerel, Cooked",                 "Fish",        262, 23.9,  0.0, 17.8),
    ("5008", "Halibut, Cooked",                  "Fish",        140, 27.2,  0.0,  2.9),
    ("5009", "Trout, Cooked",                    "Fish",        190, 26.6,  0.0,  8.5),
    ("5010", "Crab, Cooked",                     "Fish",         97, 19.4,  0.0,  1.5),
    ("5011", "Lobster, Cooked",                  "Fish",         98, 20.5,  0.5,  0.6),
    ("5012", "Scallops, Cooked",                 "Fish",        137, 17.8,  6.3,  3.4),
    ("5013", "Mussels, Cooked",                  "Fish",        172, 23.8,  7.4,  4.5),
    ("5014", "Clams, Cooked",                    "Fish",        148, 25.6,  5.1,  2.0),
    ("5015", "Tuna, Canned in Oil",              "Fish",        198, 28.9,  0.0,  8.2),

    # ── Eggs & Dairy ──────────────────────────────────────────────────────────
    ("6001", "Egg, Whole, Cooked",               "Eggs & Dairy",  155, 13.0,  1.1, 11.3),
    ("6002", "Egg White, Cooked",                "Eggs & Dairy",   52, 11.0,  0.7,  0.2),
    ("6003", "Egg Yolk",                         "Eggs & Dairy",  322, 15.9,  3.6, 26.5),
    ("6004", "Milk, Whole (3.25%)",              "Eggs & Dairy",   61,  3.2,  4.8,  3.3),
    ("6005", "Milk, 2%",                         "Eggs & Dairy",   52,  3.4,  5.0,  2.0),
    ("6006", "Milk, Skim",                       "Eggs & Dairy",   34,  3.4,  5.0,  0.2),
    ("6007", "Yogurt, Greek, Plain",             "Eggs & Dairy",   59,  9.9,  3.6,  0.4),
    ("6008", "Yogurt, Plain, Whole Milk",        "Eggs & Dairy",   61,  3.5,  4.7,  3.3),
    ("6009", "Cheddar Cheese",                   "Eggs & Dairy",  402, 25.0,  1.3, 33.0),
    ("6010", "Mozzarella Cheese",                "Eggs & Dairy",  280, 19.4,  2.2, 22.4),
    ("6011", "Parmesan Cheese",                  "Eggs & Dairy",  431, 38.5,  4.1, 28.6),
    ("6012", "Feta Cheese",                      "Eggs & Dairy",  264, 14.2,  4.1, 21.3),
    ("6013", "Ricotta Cheese, Part Skim",        "Eggs & Dairy",  138,  9.4,  5.1,  8.0),
    ("6014", "Cottage Cheese, 2%",               "Eggs & Dairy",   86, 11.6,  4.3,  2.3),
    ("6015", "Butter",                           "Eggs & Dairy",  717,  0.9,  0.1, 81.1),
    ("6016", "Cream Cheese",                     "Eggs & Dairy",  342,  6.2,  4.1, 34.2),
    ("6017", "Heavy Whipping Cream",             "Eggs & Dairy",  340,  2.1,  2.8, 36.1),
    ("6018", "Sour Cream",                       "Eggs & Dairy",  198,  2.4,  4.6, 19.4),

    # ── Grains & Bread ────────────────────────────────────────────────────────
    ("7001", "White Rice, Cooked",               "Grains",       130,  2.7, 28.2,  0.3),
    ("7002", "Brown Rice, Cooked",               "Grains",       123,  2.7, 25.6,  1.0),
    ("7003", "Pasta, Cooked",                    "Grains",       158,  5.8, 30.9,  0.9),
    ("7004", "Whole Wheat Pasta, Cooked",        "Grains",       124,  5.3, 26.5,  0.5),
    ("7005", "Oats, Cooked (Oatmeal)",           "Grains",        68,  2.4, 12.0,  1.4),
    ("7006", "Bread, White",                     "Grains",       265,  9.0, 49.2,  3.2),
    ("7007", "Bread, Whole Wheat",               "Grains",       252,  8.8, 43.1,  4.2),
    ("7008", "Quinoa, Cooked",                   "Grains",       120,  4.4, 21.3,  1.9),
    ("7009", "Barley, Cooked",                   "Grains",       123,  2.3, 28.2,  0.4),
    ("7010", "Couscous, Cooked",                 "Grains",       112,  3.8, 23.2,  0.2),
    ("7011", "Cornmeal, Cooked (Polenta)",       "Grains",        74,  1.7, 15.7,  0.5),
    ("7012", "Bagel, Plain",                     "Grains",       270, 10.1, 52.9,  1.7),
    ("7013", "Croissant",                        "Grains",       406,  8.2, 45.8, 21.0),
    ("7014", "Tortilla, Flour (10-inch)",        "Grains",       311,  8.0, 51.0,  7.3),
    ("7015", "Tortilla, Corn",                   "Grains",       218,  5.7, 45.7,  2.9),
    ("7016", "Rice Cake, Plain",                 "Grains",       387,  8.2, 81.6,  2.9),
    ("7017", "Pita Bread, White",                "Grains",       275,  9.1, 55.7,  1.2),
    ("7018", "Rye Bread",                        "Grains",       259,  8.5, 48.3,  3.3),
    ("7019", "Muffin, Blueberry",                "Grains",       377,  5.5, 54.8, 16.0),
    ("7020", "Pancake, Plain",                   "Grains",       227,  6.4, 32.9,  8.2),
    ("7021", "Waffle, Plain",                    "Grains",       291,  7.9, 36.9, 13.7),
    ("7022", "Granola, Plain",                   "Grains",       471, 10.3, 64.2, 20.3),
    ("7023", "Corn Flakes",                      "Grains",       357,  7.5, 83.6,  0.4),
    ("7024", "Oats, Rolled, Dry",                "Grains",       389, 16.9, 66.3,  6.9),

    # ── Legumes ──────────────────────────────────────────────────────────────
    ("8001", "Black Beans, Cooked",              "Legumes",      132,  8.9, 23.7,  0.5),
    ("8002", "Chickpeas, Cooked",                "Legumes",      164,  8.9, 27.4,  2.6),
    ("8003", "Lentils, Cooked",                  "Legumes",      116,  9.0, 20.1,  0.4),
    ("8004", "Kidney Beans, Cooked",             "Legumes",      127,  8.7, 22.8,  0.5),
    ("8005", "Pinto Beans, Cooked",              "Legumes",      143,  8.2, 26.8,  0.7),
    ("8006", "Edamame, Cooked",                  "Legumes",      121, 11.9,  8.9,  5.2),
    ("8007", "Tofu, Firm",                       "Legumes",       83,  9.0,  2.0,  4.8),
    ("8008", "Tofu, Silken",                     "Legumes",       55,  5.3,  2.4,  2.5),
    ("8009", "Tempeh",                           "Legumes",      195, 20.3,  7.6, 11.4),
    ("8010", "Hummus",                           "Legumes",      166,  7.9, 14.3,  9.6),
    ("8011", "Split Peas, Cooked",               "Legumes",      118,  8.3, 21.1,  0.4),
    ("8012", "Navy Beans, Cooked",               "Legumes",      140,  8.2, 26.0,  0.6),

    # ── Vegetables ───────────────────────────────────────────────────────────
    ("9001", "Broccoli, Cooked",                 "Vegetables",    35,  2.4,  7.2,  0.4),
    ("9002", "Spinach, Cooked",                  "Vegetables",    23,  3.0,  3.8,  0.3),
    ("9003", "Kale, Cooked",                     "Vegetables",    28,  1.9,  5.6,  0.4),
    ("9004", "Sweet Potato, Baked",              "Vegetables",    90,  2.0, 20.7,  0.1),
    ("9005", "Potato, Baked with Skin",          "Vegetables",    93,  2.5, 21.1,  0.1),
    ("9006", "Carrot, Raw",                      "Vegetables",    41,  0.9,  9.6,  0.2),
    ("9007", "Carrot, Cooked",                   "Vegetables",    35,  0.8,  8.2,  0.1),
    ("9008", "Tomato, Raw",                      "Vegetables",    18,  0.9,  3.9,  0.2),
    ("9009", "Cucumber, Raw",                    "Vegetables",    16,  0.7,  3.6,  0.1),
    ("9010", "Bell Pepper, Red, Raw",            "Vegetables",    31,  1.0,  6.0,  0.3),
    ("9011", "Bell Pepper, Green, Raw",          "Vegetables",    20,  0.9,  4.6,  0.2),
    ("9012", "Onion, Raw",                       "Vegetables",    40,  1.1,  9.3,  0.1),
    ("9013", "Garlic, Raw",                      "Vegetables",   149,  6.4, 33.1,  0.5),
    ("9014", "Corn, Yellow, Cooked",             "Vegetables",    96,  3.4, 21.0,  1.5),
    ("9015", "Green Peas, Cooked",               "Vegetables",    84,  5.4, 15.6,  0.2),
    ("9016", "Mushroom, White, Cooked",          "Vegetables",    28,  2.2,  5.3,  0.5),
    ("9017", "Zucchini, Cooked",                 "Vegetables",    17,  1.1,  3.4,  0.3),
    ("9018", "Cauliflower, Cooked",              "Vegetables",    23,  1.9,  4.1,  0.5),
    ("9019", "Brussels Sprouts, Cooked",         "Vegetables",    36,  2.5,  7.1,  0.5),
    ("9020", "Asparagus, Cooked",                "Vegetables",    22,  2.4,  4.0,  0.2),
    ("9021", "Green Beans, Cooked",              "Vegetables",    35,  1.9,  7.9,  0.1),
    ("9022", "Celery, Raw",                      "Vegetables",    16,  0.7,  3.0,  0.2),
    ("9023", "Lettuce, Romaine, Raw",            "Vegetables",    17,  1.2,  3.3,  0.3),
    ("9024", "Lettuce, Iceberg, Raw",            "Vegetables",    14,  0.9,  3.0,  0.1),
    ("9025", "Cabbage, Raw",                     "Vegetables",    25,  1.3,  5.8,  0.1),
    ("9026", "Cabbage, Cooked",                  "Vegetables",    23,  1.3,  5.4,  0.1),
    ("9027", "Eggplant, Cooked",                 "Vegetables",    35,  0.8,  8.7,  0.2),
    ("9028", "Artichoke, Cooked",                "Vegetables",    53,  2.9, 12.4,  0.2),
    ("9029", "Avocado",                          "Vegetables",   160,  2.0,  8.5, 14.7),
    ("9030", "Pumpkin, Cooked",                  "Vegetables",    26,  1.0,  6.5,  0.1),
    ("9031", "Leek, Cooked",                     "Vegetables",    31,  0.8,  7.6,  0.2),
    ("9032", "Beet, Cooked",                     "Vegetables",    44,  1.7, 10.0,  0.1),
    ("9033", "Turnip, Cooked",                   "Vegetables",    22,  0.7,  4.9,  0.1),
    ("9034", "Yam, Baked",                       "Vegetables",   116,  1.5, 27.5,  0.1),
    ("9035", "Bok Choy, Cooked",                 "Vegetables",    12,  1.6,  1.8,  0.2),

    # ── Fruits ────────────────────────────────────────────────────────────────
    ("10001", "Apple",                           "Fruits",        52,  0.3, 13.8,  0.2),
    ("10002", "Banana",                          "Fruits",        89,  1.1, 22.8,  0.3),
    ("10003", "Orange",                          "Fruits",        47,  0.9, 11.8,  0.1),
    ("10004", "Mango",                           "Fruits",        60,  0.8, 15.0,  0.4),
    ("10005", "Strawberry",                      "Fruits",        32,  0.7,  7.7,  0.3),
    ("10006", "Blueberry",                       "Fruits",        57,  0.7, 14.5,  0.3),
    ("10007", "Grape, Red",                      "Fruits",        69,  0.7, 18.1,  0.2),
    ("10008", "Watermelon",                      "Fruits",        30,  0.6,  7.6,  0.2),
    ("10009", "Pineapple",                       "Fruits",        50,  0.5, 13.1,  0.1),
    ("10010", "Peach",                           "Fruits",        39,  0.9,  9.5,  0.3),
    ("10011", "Pear",                            "Fruits",        57,  0.4, 15.2,  0.1),
    ("10012", "Kiwi",                            "Fruits",        61,  1.1, 14.7,  0.5),
    ("10013", "Cherry, Sweet",                   "Fruits",        63,  1.1, 16.0,  0.2),
    ("10014", "Plum",                            "Fruits",        46,  0.7, 11.4,  0.3),
    ("10015", "Pomegranate",                     "Fruits",        83,  1.7, 18.7,  1.2),
    ("10016", "Raspberry",                       "Fruits",        52,  1.2, 11.9,  0.7),
    ("10017", "Blackberry",                      "Fruits",        43,  1.4,  9.6,  0.5),
    ("10018", "Lemon",                           "Fruits",        29,  1.1,  9.3,  0.3),
    ("10019", "Lime",                            "Fruits",        30,  0.7, 10.5,  0.2),
    ("10020", "Grapefruit",                      "Fruits",        42,  0.8, 10.7,  0.1),
    ("10021", "Cantaloupe",                      "Fruits",        34,  0.8,  8.2,  0.2),
    ("10022", "Papaya",                          "Fruits",        43,  0.5, 10.8,  0.3),
    ("10023", "Fig",                             "Fruits",        74,  0.8, 19.2,  0.3),
    ("10024", "Date, Medjool",                   "Fruits",       277,  1.8, 75.0,  0.2),

    # ── Nuts & Seeds ──────────────────────────────────────────────────────────
    ("11001", "Almonds",                         "Nuts & Seeds",  579, 21.2, 21.6, 49.9),
    ("11002", "Walnuts",                         "Nuts & Seeds",  654, 15.2, 13.7, 65.2),
    ("11003", "Cashews",                         "Nuts & Seeds",  553, 18.2, 30.2, 43.9),
    ("11004", "Peanuts",                         "Nuts & Seeds",  567, 25.8, 16.1, 49.2),
    ("11005", "Peanut Butter, Creamy",           "Nuts & Seeds",  588, 25.1, 20.1, 50.4),
    ("11006", "Almond Butter",                   "Nuts & Seeds",  614, 21.1, 18.8, 55.5),
    ("11007", "Sunflower Seeds",                 "Nuts & Seeds",  584, 20.8, 20.0, 51.5),
    ("11008", "Pumpkin Seeds",                   "Nuts & Seeds",  559, 30.2,  1.4, 49.1),
    ("11009", "Chia Seeds",                      "Nuts & Seeds",  486, 16.5, 42.1, 30.7),
    ("11010", "Flaxseeds",                       "Nuts & Seeds",  534, 18.3, 28.9, 42.2),
    ("11011", "Pistachios",                      "Nuts & Seeds",  560, 20.6, 27.5, 45.3),
    ("11012", "Macadamia Nuts",                  "Nuts & Seeds",  718,  7.9, 13.8, 75.8),
    ("11013", "Pecans",                          "Nuts & Seeds",  691,  9.2, 13.9, 72.0),
    ("11014", "Hazelnuts",                       "Nuts & Seeds",  628, 15.0, 16.7, 60.8),
    ("11015", "Sesame Seeds",                    "Nuts & Seeds",  573, 17.7, 23.5, 49.7),
    ("11016", "Hemp Seeds",                      "Nuts & Seeds",  553, 31.6,  8.7, 48.8),
    ("11017", "Brazil Nuts",                     "Nuts & Seeds",  659, 14.3, 12.3, 67.1),

    # ── Oils & Fats ──────────────────────────────────────────────────────────
    ("12001", "Olive Oil",                       "Oils & Fats",   884,  0.0,  0.0,100.0),
    ("12002", "Coconut Oil",                     "Oils & Fats",   862,  0.0,  0.0,100.0),
    ("12003", "Vegetable Oil",                   "Oils & Fats",   884,  0.0,  0.0,100.0),
    ("12004", "Canola Oil",                      "Oils & Fats",   884,  0.0,  0.0,100.0),
    ("12005", "Avocado Oil",                     "Oils & Fats",   884,  0.0,  0.0,100.0),
    ("12006", "Sesame Oil",                      "Oils & Fats",   884,  0.0,  0.0,100.0),
    ("12007", "Ghee",                            "Oils & Fats",   900,  0.0,  0.0, 99.8),
    ("12008", "Lard",                            "Oils & Fats",   902,  0.0,  0.0,100.0),
    ("12009", "Margarine",                       "Oils & Fats",   717,  0.2,  0.7, 80.7),
    ("12010", "Mayonnaise",                      "Oils & Fats",   680,  1.0,  0.6, 74.9),

    # ── Snacks & Fast Food ────────────────────────────────────────────────────
    ("13001", "Potato Chips",                    "Snacks",        536,  7.0, 53.0, 35.0),
    ("13002", "Popcorn, Air-Popped",             "Snacks",        387, 13.0, 78.0,  4.5),
    ("13003", "Pretzels",                        "Snacks",        380, 10.0, 80.0,  3.5),
    ("13004", "Crackers, Saltine",               "Snacks",        421,  9.8, 74.0,  8.7),
    ("13005", "Rice Crackers",                   "Snacks",        392,  9.0, 86.0,  1.0),
    ("13006", "Chocolate, Dark (70%)",           "Snacks",        600,  7.8, 46.4, 42.6),
    ("13007", "Chocolate, Milk",                 "Snacks",        535,  7.7, 59.4, 29.7),
    ("13008", "Ice Cream, Vanilla",              "Snacks",        207,  3.5, 23.6, 11.0),
    ("13009", "Cookies, Chocolate Chip",         "Snacks",        488,  5.4, 65.0, 23.5),
    ("13010", "Donut, Glazed",                   "Snacks",        452,  5.0, 51.0, 25.0),
    ("13011", "French Fries",                    "Snacks",        312,  3.4, 41.4, 15.0),
    ("13012", "Hamburger, Plain",                "Snacks",        254, 14.9, 23.5, 10.7),
    ("13013", "Pizza, Cheese Slice",             "Snacks",        266, 11.4, 33.1,  9.8),
    ("13014", "Hot Dog, Plain",                  "Snacks",        290, 10.6,  2.9, 26.1),
    ("13015", "Tortilla Chips",                  "Snacks",        489,  7.3, 64.0, 23.4),
    ("13016", "Granola Bar",                     "Snacks",        471, 10.3, 64.2, 20.3),
    ("13017", "Protein Bar, Average",            "Snacks",        385, 30.0, 40.0,  8.0),

    # ── Beverages ─────────────────────────────────────────────────────────────
    ("14001", "Orange Juice",                    "Beverages",      45,  0.7, 10.4,  0.2),
    ("14002", "Apple Juice",                     "Beverages",      46,  0.1, 11.4,  0.1),
    ("14003", "Whole Milk",                      "Beverages",      61,  3.2,  4.8,  3.3),
    ("14004", "Coffee, Black",                   "Beverages",       2,  0.3,  0.0,  0.0),
    ("14005", "Coffee with Milk",                "Beverages",      13,  0.7,  1.5,  0.5),
    ("14006", "Green Tea",                       "Beverages",       1,  0.2,  0.2,  0.0),
    ("14007", "Cola, Regular",                   "Beverages",      42,  0.0, 10.6,  0.0),
    ("14008", "Beer, Regular",                   "Beverages",      43,  0.5,  3.6,  0.0),
    ("14009", "Wine, Red",                       "Beverages",      85,  0.1,  2.6,  0.0),
    ("14010", "Wine, White",                     "Beverages",      82,  0.1,  2.6,  0.0),
    ("14011", "Smoothie, Fruit",                 "Beverages",      63,  0.8, 15.0,  0.3),
    ("14012", "Protein Shake, Chocolate",        "Beverages",      80, 15.0,  6.0,  1.5),
    ("14013", "Sports Drink (Gatorade)",         "Beverages",      26,  0.0,  7.0,  0.0),
    ("14014", "Energy Drink",                    "Beverages",      45,  0.5, 11.0,  0.0),
    ("14015", "Coconut Water",                   "Beverages",      19,  0.7,  3.7,  0.2),
    ("14016", "Almond Milk, Unsweetened",        "Beverages",      17,  0.6,  0.3,  1.4),
    ("14017", "Oat Milk",                        "Beverages",      47,  1.0,  8.0,  1.5),
    ("14018", "Soy Milk",                        "Beverages",      54,  3.3,  6.3,  1.8),

    # ── Condiments & Sauces ──────────────────────────────────────────────────
    ("15001", "Ketchup",                         "Condiments",    101,  1.0, 25.0,  0.1),
    ("15002", "Mustard, Yellow",                 "Condiments",     66,  4.4,  6.0,  3.7),
    ("15003", "Soy Sauce",                       "Condiments",     53,  8.1,  4.9,  0.6),
    ("15004", "Hot Sauce",                       "Condiments",     11,  0.5,  2.0,  0.4),
    ("15005", "BBQ Sauce",                       "Condiments",    172,  0.9, 40.0,  1.0),
    ("15006", "Ranch Dressing",                  "Condiments",    486,  1.6,  5.6, 51.0),
    ("15007", "Caesar Dressing",                 "Condiments",    480,  2.5,  1.5, 52.0),
    ("15008", "Salsa",                           "Condiments",     36,  1.7,  7.0,  0.4),
    ("15009", "Guacamole",                       "Condiments",    157,  2.0,  8.6, 14.7),
    ("15010", "Honey",                           "Condiments",    304,  0.3, 82.4,  0.0),
    ("15011", "Maple Syrup",                     "Condiments",    260,  0.0, 67.0,  0.1),
    ("15012", "Jam / Jelly",                     "Condiments",    250,  0.4, 65.0,  0.1),
    ("15013", "Cream of Tomato Soup",            "Condiments",     72,  1.8, 11.5,  2.2),
    ("15014", "Worcestershire Sauce",            "Condiments",     78,  0.0, 19.6,  0.0),
    ("15015", "Teriyaki Sauce",                  "Condiments",     89,  5.1, 15.3,  0.0),

    # ── Processed & Packaged ─────────────────────────────────────────────────
    ("16001", "Canned Tuna, Water, Drained",     "Packaged",      116, 25.5,  0.0,  0.8),
    ("16002", "Canned Salmon",                   "Packaged",      139, 19.8,  0.0,  6.3),
    ("16003", "Canned Chicken",                  "Packaged",      130, 20.0,  2.0,  5.0),
    ("16004", "Deli Turkey Breast",              "Packaged",       89, 17.6,  1.7,  1.0),
    ("16005", "Deli Ham",                        "Packaged",      107, 16.6,  1.8,  3.5),
    ("16006", "Pepperoni",                       "Packaged",      494, 21.0,  0.0, 44.8),
    ("16007", "Salami",                          "Packaged",      336, 22.7,  1.2, 26.6),
    ("16008", "White Bread, Sliced",             "Packaged",      265,  9.0, 49.2,  3.2),
    ("16009", "Canned Chickpeas",                "Packaged",      164,  8.9, 27.4,  2.6),
    ("16010", "Canned Kidney Beans",             "Packaged",      127,  8.7, 22.8,  0.5),
    ("16011", "Instant Noodles, Cooked",         "Packaged",      138,  3.2, 20.5,  4.8),
    ("16012", "Frozen Corn",                     "Packaged",       86,  3.2, 20.6,  1.2),
    ("16013", "Frozen Peas",                     "Packaged",       81,  5.4, 14.5,  0.4),
    ("16014", "Frozen Broccoli",                 "Packaged",       34,  2.8,  6.6,  0.3),

    # ── Breakfast Items ───────────────────────────────────────────────────────
    ("17001", "Cereal, Oat-Based",               "Breakfast",     379, 13.3, 67.0,  6.5),
    ("17002", "Granola with Raisins",            "Breakfast",     388,  9.0, 65.0, 12.0),
    ("17003", "Pancake Syrup",                   "Breakfast",     270,  0.0, 67.0,  0.0),
    ("17004", "Cream of Wheat, Cooked",          "Breakfast",      65,  1.7, 13.2,  0.3),
    ("17005", "Breakfast Burrito",               "Breakfast",     215, 10.4, 21.5,  9.5),

    # ── Mixed Dishes ──────────────────────────────────────────────────────────
    ("18001", "Fried Rice, Chicken",             "Mixed Dishes",  163,  7.3, 25.7,  3.3),
    ("18002", "Caesar Salad",                    "Mixed Dishes",  190,  4.9,  8.3, 16.5),
    ("18003", "Greek Salad",                     "Mixed Dishes",   74,  3.2,  6.2,  4.9),
    ("18004", "Chicken Stir-Fry",                "Mixed Dishes",  118, 11.8,  8.7,  4.1),
    ("18005", "Beef Tacos (2)",                  "Mixed Dishes",  250, 13.0, 23.0, 11.0),
    ("18006", "Spaghetti with Meat Sauce",       "Mixed Dishes",  182,  9.0, 22.0,  5.5),
    ("18007", "Chicken Curry with Rice",         "Mixed Dishes",  189, 12.0, 22.0,  5.5),
    ("18008", "Salmon Sushi (1 piece)",          "Mixed Dishes",   35,  2.0,  4.8,  0.8),
    ("18009", "California Roll (1 piece)",       "Mixed Dishes",   33,  1.2,  5.5,  0.8),
    ("18010", "Pad Thai",                        "Mixed Dishes",  225,  8.0, 32.0,  7.5),
    ("18011", "Burrito Bowl, Chicken",           "Mixed Dishes",  370, 28.0, 45.0,  8.0),
    ("18012", "Soup, Chicken Noodle",            "Mixed Dishes",   62,  4.1,  7.3,  1.4),
    ("18013", "Soup, Tomato",                    "Mixed Dishes",   72,  1.8, 11.5,  2.2),
    ("18014", "Chili with Beans",                "Mixed Dishes",  152,  9.6, 16.5,  4.9),
    ("18015", "Mac and Cheese",                  "Mixed Dishes",  350,  9.0, 40.0, 17.0),
    ("18016", "Lasagna, Meat",                   "Mixed Dishes",  168,  9.0, 17.5,  6.5),
    ("18017", "Omelette, Plain",                 "Mixed Dishes",  154, 11.0,  0.5, 12.0),
    ("18018", "Scrambled Eggs",                  "Mixed Dishes",  148, 10.1,  1.6, 11.2),
    ("18019", "Smoothie Bowl",                   "Mixed Dishes",  146,  5.0, 25.0,  3.5),
    ("18020", "Acai Bowl",                       "Mixed Dishes",  211,  4.0, 32.0,  8.0),
]

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

def main():
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    assets_dir = os.path.join(repo_root, "assets")
    os.makedirs(assets_dir, exist_ok=True)
    db_path = os.path.join(assets_dir, "food_db.sqlite")

    if os.path.exists(db_path):
        os.remove(db_path)

    conn = sqlite3.connect(db_path)
    cur = conn.cursor()

    # Main table
    cur.execute("""
        CREATE TABLE foods (
            id       TEXT PRIMARY KEY,
            name     TEXT NOT NULL,
            category TEXT,
            cal      REAL NOT NULL,
            protein  REAL,
            carbs    REAL,
            fat      REAL
        )
    """)

    # FTS5 virtual table for fast prefix search
    cur.execute("""
        CREATE VIRTUAL TABLE foods_fts USING fts5(
            name,
            content='foods',
            content_rowid='rowid'
        )
    """)

    # Trigger to keep FTS in sync on insert
    cur.execute("""
        CREATE TRIGGER foods_ai AFTER INSERT ON foods BEGIN
            INSERT INTO foods_fts(rowid, name) VALUES (new.rowid, new.name);
        END
    """)

    cur.executemany(
        "INSERT INTO foods (id, name, category, cal, protein, carbs, fat) VALUES (?,?,?,?,?,?,?)",
        FOODS,
    )

    conn.commit()

    # Compact the file
    cur.execute("VACUUM")
    conn.close()

    size_kb = os.path.getsize(db_path) / 1024
    print(f"OK: {db_path}")
    print(f"  {len(FOODS)} foods  |  {size_kb:.1f} KB")


if __name__ == "__main__":
    main()
