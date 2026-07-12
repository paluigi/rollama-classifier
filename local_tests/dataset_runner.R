# Shared dataset evaluation helper for local_tests
#
# Contains the test dataset and a runner that classifies every entry with both
# classify() and generate(), then writes results to a timestamped CSV.
#
# A "none_of_the_above" choice is appended to the category list so the model
# can express that no category fits -- its probability is reported in the
# prob_none column.

# ---------------------------------------------------------------------------
# Dataset
# ---------------------------------------------------------------------------

data_json <- list(
  categories = c(
    "technology",
    "food_cooking",
    "sports_fitness",
    "finance_investing",
    "travel_tourism"
  ),
  dataset = list(
    list(id = 1L, text = "The new smartphone features an upgraded octa-core processor and 12GB of RAM for seamless multitasking.", ambiguity_level = "clear", primary_category = "technology", secondary_category = NULL),
    list(id = 2L, text = "I need to update my operating system because some software applications are crashing on startup.", ambiguity_level = "clear", primary_category = "technology", secondary_category = NULL),
    list(id = 3L, text = "Cloud computing allows businesses to scale their server infrastructure dynamically based on demand.", ambiguity_level = "clear", primary_category = "technology", secondary_category = NULL),
    list(id = 4L, text = "Whisk the egg whites until stiff peaks form before gently folding them into the cake batter.", ambiguity_level = "clear", primary_category = "food_cooking", secondary_category = NULL),
    list(id = 5L, text = "This local Italian restaurant serves authentic wood-fired Neapolitan pizza with fresh basil and mozzarella.", ambiguity_level = "clear", primary_category = "food_cooking", secondary_category = NULL),
    list(id = 6L, text = "Slow-roasting garlic in olive oil at a low temperature produces a sweet, spreadable paste.", ambiguity_level = "clear", primary_category = "food_cooking", secondary_category = NULL),
    list(id = 7L, text = "The striker scored a stunning hat-trick in the second half to secure a victory for his team.", ambiguity_level = "clear", primary_category = "sports_fitness", secondary_category = NULL),
    list(id = 8L, text = "Proper hydration and stretching before running a marathon are essential to prevent muscle cramps.", ambiguity_level = "clear", primary_category = "sports_fitness", secondary_category = NULL),
    list(id = 9L, text = "Our local basketball league is looking for new referees to officiate the upcoming weekend games.", ambiguity_level = "clear", primary_category = "sports_fitness", secondary_category = NULL),
    list(id = 10L, text = "Diversifying your investment portfolio across stocks, bonds, and real estate helps mitigate risk.", ambiguity_level = "clear", primary_category = "finance_investing", secondary_category = NULL),
    list(id = 11L, text = "The central bank decided to raise interest rates to curb rising inflation across the country.", ambiguity_level = "clear", primary_category = "finance_investing", secondary_category = NULL),
    list(id = 12L, text = "Opening a high-yield savings account is a simple way to earn interest on your emergency fund.", ambiguity_level = "clear", primary_category = "finance_investing", secondary_category = NULL),
    list(id = 13L, text = "We spent the afternoon exploring the historic ruins of Rome and taking photos of the Colosseum.", ambiguity_level = "clear", primary_category = "travel_tourism", secondary_category = NULL),
    list(id = 14L, text = "Remember to check the visa requirements and passport validity before booking your flights abroad.", ambiguity_level = "clear", primary_category = "travel_tourism", secondary_category = NULL),
    list(id = 15L, text = "The boutique hotel offers stunning ocean views and is located just steps from the sandy beach.", ambiguity_level = "clear", primary_category = "travel_tourism", secondary_category = NULL),
    list(id = 16L, text = "Backpacking through Southeast Asia is an affordable way for students to experience diverse cultures.", ambiguity_level = "clear", primary_category = "travel_tourism", secondary_category = NULL),
    list(id = 17L, text = "This new smart air fryer connects to your home Wi-Fi, allowing you to monitor cooking progress from an app.", ambiguity_level = "mildly_ambiguous", primary_category = "technology", secondary_category = "food_cooking"),
    list(id = 18L, text = "I bought a premium smartwatch to track my daily steps, heart rate variability, and GPS routes during morning jogs.", ambiguity_level = "mildly_ambiguous", primary_category = "technology", secondary_category = "sports_fitness"),
    list(id = 19L, text = "While wandering the streets of Paris, I stumbled upon a tiny bakery serving the most incredible butter croissants.", ambiguity_level = "mildly_ambiguous", primary_category = "food_cooking", secondary_category = "travel_tourism"),
    list(id = 20L, text = "I used a digital kitchen scale and a specialized molecular gastronomy calculator to measure the sodium alginate for this recipe.", ambiguity_level = "mildly_ambiguous", primary_category = "food_cooking", secondary_category = "technology"),
    list(id = 21L, text = "The professional football player signed a multi-million dollar contract extension, making him the highest-paid athlete this season.", ambiguity_level = "mildly_ambiguous", primary_category = "sports_fitness", secondary_category = "finance_investing"),
    list(id = 22L, text = "The cycling team utilized wind-tunnel data and advanced computational fluid dynamics software to optimize their riding postures.", ambiguity_level = "mildly_ambiguous", primary_category = "sports_fitness", secondary_category = "technology"),
    list(id = 23L, text = "The sudden surge in cryptocurrency trading caused several online brokerage platforms to experience temporary server outages.", ambiguity_level = "mildly_ambiguous", primary_category = "finance_investing", secondary_category = "technology"),
    list(id = 24L, text = "Many digital nomads set up offshore bank accounts to optimize their tax liabilities while moving between different countries.", ambiguity_level = "mildly_ambiguous", primary_category = "finance_investing", secondary_category = "travel_tourism"),
    list(id = 25L, text = "Budgeting for a year-long trip around the world requires calculating daily accommodation costs and saving thousands in advance.", ambiguity_level = "mildly_ambiguous", primary_category = "travel_tourism", secondary_category = "finance_investing"),
    list(id = 26L, text = "The culinary tourism package includes guided street food tours and private cooking classes with local chefs in Tokyo.", ambiguity_level = "mildly_ambiguous", primary_category = "travel_tourism", secondary_category = "food_cooking"),
    list(id = 27L, text = "Rising grain prices and supply chain disruptions are forcing local artisan bakeries to increase the cost of a sourdough loaf.", ambiguity_level = "mildly_ambiguous", primary_category = "food_cooking", secondary_category = "finance_investing"),
    list(id = 28L, text = "The software company introduced a new subscription model for its cloud services, aiming to boost recurring software-as-a-service revenues.", ambiguity_level = "mildly_ambiguous", primary_category = "technology", secondary_category = "finance_investing"),
    list(id = 29L, text = "Our amateur soccer club is traveling to Spain next month to participate in an international friendly tournament.", ambiguity_level = "mildly_ambiguous", primary_category = "sports_fitness", secondary_category = "travel_tourism"),
    list(id = 30L, text = "Investing in premium sports memorabilia, like game-worn jerseys, has become a highly lucrative alternative asset class.", ambiguity_level = "mildly_ambiguous", primary_category = "finance_investing", secondary_category = "sports_fitness"),
    list(id = 31L, text = "This article reviews the engineering behind elite running shoes, comparing the energy-return polymer plates with smart embedded pressure sensors.", ambiguity_level = "highly_ambiguous", primary_category = "technology", secondary_category = "sports_fitness"),
    list(id = 32L, text = "Mobile banking apps are leveraging decentralized blockchain protocols and biometric authentication to secure financial transactions.", ambiguity_level = "highly_ambiguous", primary_category = "technology", secondary_category = "finance_investing"),
    list(id = 33L, text = "A comprehensive guide to exploring the night markets of Taiwan, focusing on the history of regional street food and how to navigate the crowded stalls.", ambiguity_level = "highly_ambiguous", primary_category = "food_cooking", secondary_category = "travel_tourism"),
    list(id = 34L, text = "An analysis of the global coffee bean futures market, discussing how climate change impacts crop yields and the final retail price of espresso.", ambiguity_level = "highly_ambiguous", primary_category = "food_cooking", secondary_category = "finance_investing"),
    list(id = 35L, text = "Hiking the Pacific Crest Trail: A detailed breakdown of the physical conditioning required for high-altitude trekking and the logistics of navigating national parks.", ambiguity_level = "highly_ambiguous", primary_category = "sports_fitness", secondary_category = "travel_tourism"),
    list(id = 36L, text = "A sports nutritionist's guide to meal prepping, detailing exactly what macro-nutrients to eat before high-intensity interval training to maximize muscle recovery.", ambiguity_level = "highly_ambiguous", primary_category = "sports_fitness", secondary_category = "food_cooking"),
    list(id = 37L, text = "Agriculture technology is evolving rapidly, with automated indoor hydroponic systems using AI sensors to deliver nutrients to crops without soil.", ambiguity_level = "highly_ambiguous", primary_category = "technology", secondary_category = "food_cooking"),
    list(id = 38L, text = "Analyzing the economic impact of international tourism on developing island nations, specifically tracking foreign currency exchange and hotel industry revenues.", ambiguity_level = "highly_ambiguous", primary_category = "finance_investing", secondary_category = "travel_tourism"),
    list(id = 39L, text = "The chemical structure of DNA consists of two long chains of nucleotides twisted into a double helix.", ambiguity_level = "out_of_scope", primary_category = NULL, secondary_category = NULL),
    list(id = 40L, text = "William Shakespeare's tragedy 'Hamlet' explores themes of revenge, madness, and moral corruption in the Danish court.", ambiguity_level = "out_of_scope", primary_category = NULL, secondary_category = NULL)
  )
)

# The "none of the above" choice appended so the model can reject all categories
NONE_CHOICE <- "none_of_the_above"


#' Run the dataset through classify() and generate(), save to CSV
#'
#' @param classifier An llm_classifier object.
#' @param backend_name Short backend name (e.g. "ollama").
#' @param llm_name Model name (e.g. "qwen2.5:3b-instruct").
#' @return The path to the generated CSV file.
run_dataset_and_save_csv <- function(classifier, backend_name, llm_name) {
  categories <- data_json$categories
  entries <- data_json$dataset

  # Choices presented to the classifier: real categories + none_of_the_above
  choices <- c(categories, NONE_CHOICE)

  timestamp <- format(Sys.time(), "%Y%m%d%H%M%S")
  csv_path <- file.path(getwd(), sprintf("%s_%s.csv", backend_name, timestamp))

  rows <- list()

  for (entry in entries) {
    text <- entry$text

    for (api_name in c("classify", "generate")) {
      if (api_name == "classify") {
        result <- classify(classifier, text = text, choices = choices)
      } else {
        result <- generate(classifier, text = text, choices = choices, max_calls = 1L)
      }

      row <- list(
        id = entry$id,
        text = text,
        ambiguity_level = entry$ambiguity_level,
        primary_category = entry$primary_category %||% "",
        secondary_category = entry$secondary_category %||% "",
        backend = backend_name,
        llm = llm_name,
        api = api_name,
        prediction = result$prediction,
        confidence = sprintf("%.6f", result$confidence)
      )
      for (cat in categories) {
        row[[paste0("prob_", cat)]] <- sprintf("%.6f", result$probabilities[[cat]] %||% 0.0)
      }
      row[["prob_none"]] <- sprintf("%.6f", result$probabilities[[NONE_CHOICE]] %||% 0.0)
      rows <- c(rows, list(row))
    }
  }

  # Write CSV
  fieldnames <- c(
    "id", "text", "ambiguity_level", "primary_category", "secondary_category",
    "backend", "llm", "api", "prediction", "confidence",
    paste0("prob_", categories), "prob_none"
  )

  con <- file(csv_path, "w", encoding = "UTF-8")
  on.exit(close(con), add = TRUE)
  writeLines(paste(fieldnames, collapse = ","), con)
  for (row in rows) {
    values <- purrr::map_chr(fieldnames, ~ {
      v <- row[[.x]]
      if (is.null(v)) "" else sprintf('"%s"', gsub('"', '""', as.character(v)))
    })
    writeLines(paste(values, collapse = ","), con)
  }

  cat(sprintf("\n  CSV saved: %s (%d rows)\n", csv_path, length(rows)))
  csv_path
}
