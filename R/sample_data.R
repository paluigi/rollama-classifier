#' Sample Data for Testing rollama
#'
#' Two ready-to-use datasets for text classification, each containing 20
#' customer support ticket texts across four categories: billing,
#' Sample Data for Testing rollama
#'
#' @name sample_tickets
#' @docType data
#' @keywords data
#'
#' @format A data frame with 20 rows and 4 columns:
#' \describe{
#'   \item{text}{Character. Short text to classify.}
#'   \item{expected_label}{Character. Expected correct label.}
#'   \item{label}{Character. Simple category label.}
#'   \item{label_description}{Character. Human-readable description of the
#'     category.}
#' }
#'
#' @source Internal dataset
NULL

texts <- c(
  # billing (5)
  "I was charged twice for my last order",
  "Can I get a refund for the subscription I cancelled last week?",
  "My invoice shows a different amount than what was quoted",
  "Where can I find my payment history?",
  "I need an update on my pending refund",
  # technical_support (5)
  "The app keeps crashing when I try to upload a file",
  "I can't log in to my account after the latest update",
  "The page loads very slowly on mobile devices",
  "How do I reset my password if I don't have access to my email?",
  "I'm getting a 404 error on the dashboard",
  # account (5)
  "How do I change the email address on my profile?",
  "I'd like to delete my account and all associated data",
  "Can I upgrade from the free plan to the premium plan?",
  "How do I add a second user to my team account?",
  "I need to update my billing address",
  # general (5)
  "What are your business hours?",
  "Is there a mobile app available?",
  "Do you offer discounts for non-profit organizations?",
  "Where can I find your privacy policy?",
  "How do I contact your customer support team?"
)

labels <- c("billing", "technical_support", "account", "general")

labels_with_descriptions <- list(
  billing = "Questions about charges, invoices, payments, refunds, and subscription costs",
  technical_support = "Issues with software, bugs, errors, login problems, or performance",
  account = "Requests to manage profile settings, plans, team members, or data",
  general = "General inquiries about the company, policies, hours, or availability"
)

expected_labels <- c(
  # billing
  "billing", "billing", "billing", "billing", "billing",
  # technical_support
  "technical_support", "technical_support", "technical_support",
  "technical_support", "technical_support",
  # account
  "account", "account", "account", "account", "account",
  # general
  "general", "general", "general", "general", "general"
)

#' @rdname sample_tickets
"sample_tickets" <- tibble::tibble(
  text = texts,
  expected_label = expected_labels,
  label = rep(labels, each = 5),
  label_description = rep(unlist(labels_with_descriptions), each = 5)
)

utils::globalVariables("sample_tickets")
