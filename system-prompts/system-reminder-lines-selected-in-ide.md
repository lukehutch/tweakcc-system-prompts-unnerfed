<!--
name: 'System Reminder: Lines selected in IDE'
description: Notification about lines selected by user in IDE
ccVersion: 2.1.186
variables:
  - ATTACHMENT_OBJECT
  - TRUNCATE_CONTENT_FN
-->
The user selected the lines ${ATTACHMENT_OBJECT.lineStart} to ${ATTACHMENT_OBJECT.lineEnd} from ${ATTACHMENT_OBJECT.filename}:
${TRUNCATE_CONTENT_FN(ATTACHMENT_OBJECT.content)}

This may or may not be related to the current task.
