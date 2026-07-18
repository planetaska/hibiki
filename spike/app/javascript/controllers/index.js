// Import and register all your controllers from the importmap via controllers/**/*_controller
import { application } from "controllers/application"
import { eagerLoadControllersFrom } from "@hotwired/stimulus-loading"
eagerLoadControllersFrom("controllers", application)
// The packaged hibiki client is registered by the eager-loaded
// hibiki_controller.js shim (file-backed so stimulus:manifest:update
// can't drop it).
