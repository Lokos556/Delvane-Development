# Rosa v2.10.96 — UI background fix

- Removed the global `background-color: #FFFFFF !important` rule that forced every DOM element, including text containers and inline elements, to have a white background.
- Kept the existing targeted yellow accent rules and did not modify authentication, reservations, OCR, Channex, or backend logic.
- Bumped CSS and app asset query versions to 2.10.96 to avoid reusing cached frontend assets.

Validation: checked that the problematic universal white-background rule is absent and that the HTML references styles.css/app.js with v=2.10.96. This package has not been launched in a browser, so visual verification still needs to be done on your machine.
