// Import and register all your controllers from the importmap via controllers/**/*_controller
import { application } from "controllers/application"
import { eagerLoadControllersFrom } from "@hotwired/stimulus-loading"
eagerLoadControllersFrom("controllers", application)

// The packaged hibiki client (vendored by the hibiki_rails engine, pinned
// as "hibiki"). The identifier must be "hibiki" — the Ruby helpers
// hardcode it in data-controller.
import HibikiController from "hibiki"
application.register("hibiki", HibikiController)
