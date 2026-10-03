import QtQuick
import qs.Commons
import qs.Ui
import "../Model.js" as Model

// Project, activity, description and tags: shared by StartForm and EditForm.
// Projects carry their customer as the option description, so searching
// either name finds them.
Column {
  id: root

  property var svc: null
  property string projectId: ""
  property string activityId: ""
  property var selectedTags: []
  property var projectOptions: []
  property var activityOptions: []
  property var tagOptions: []
  // Names from the prefill: shown until the lists load, and kept when the
  // entry's project or activity is hidden/archived and missing from them.
  property string _projectLabel: ""
  property string _activityLabel: ""
  property alias description: descriptionField.text
  readonly property var tags: Model.mergeTags(root.selectedTags, newTagsField.text)
  readonly property bool textEditing: descriptionField.activeFocus || newTagsField.activeFocus

  signal submitted()
  // Any change made by the user (not by reset()).
  signal edited()

  spacing: Style.space(8)

  // prefill: Model.prefillFromEntry(...). Until Kimai's lists arrive the
  // pickers show the prefill's names instead of bare ids.
  function reset(prefill) {
    root.projectId = prefill.projectId
    root.activityId = prefill.activityId
    root.selectedTags = prefill.tags
    descriptionField.text = prefill.description
    newTagsField.text = ""
    root._projectLabel = prefill.projectLabel || ""
    root._activityLabel = prefill.activityLabel || ""
    root.projectOptions = root.withOption(root.projectOptions, prefill.projectId, root._projectLabel)
    root.activityOptions = root.withOption([], prefill.activityId, root._activityLabel)
    if (!root.svc) return
    root.svc.projects(function(r) {
      if (r.kind === "ok") root.projectOptions = root.withOption(Model.toOptions(r.data), root.projectId, root._projectLabel)
    })
    root.svc.tags(function(r) { if (r.kind === "ok") root.tagOptions = Model.tagOptions(r.data) })
    root.loadActivities(false)
  }

  function withOption(options, value, label) {
    if (!value || !label) return options
    for (var i = 0; i < options.length; i++) if (options[i].value === value) return options
    return options.concat([{ value: value, label: label, description: "" }])
  }

  // clear: drop the current list first (the project changed, so it is stale).
  function loadActivities(clear) {
    if (clear) root.activityOptions = []
    if (!root.svc || !root.projectId) return
    var forProject = root.projectId
    root.svc.activities(forProject, function(r) {
      if (r.kind === "ok" && forProject === root.projectId)
        root.activityOptions = root.withOption(Model.toOptions(r.data), root.activityId, root._activityLabel)
    })
  }

  SearchableDropdown {
    width: parent.width
    label: "Project"
    triggerLabel: "Choose a project"
    placeholderText: "Search projects or customers…"
    options: root.projectOptions
    value: root.projectId
    onChanged: function(value) {
      root.projectId = value
      root.activityId = ""
      root._activityLabel = ""
      root.loadActivities(true)
      root.edited()
    }
  }

  SearchableDropdown {
    width: parent.width
    label: "Activity"
    triggerLabel: root.projectId ? "Choose an activity" : "Choose a project first"
    placeholderText: "Search activities…"
    enabled: root.projectId !== ""
    options: root.activityOptions
    value: root.activityId
    onChanged: function(value) { root.activityId = value; root.edited() }
  }

  TextField {
    id: descriptionField
    width: parent.width
    placeholderText: "What are you working on?"
    onAccepted: root.submitted()
    onTextEdited: root.edited()
  }

  MultiSelect {
    width: parent.width
    label: "Tags"
    noSelectionText: "No tags"
    options: root.tagOptions
    values: root.selectedTags
    onChanged: function(values) { root.selectedTags = values; root.edited() }
  }

  TextField {
    id: newTagsField
    width: parent.width
    placeholderText: "New tags, comma separated"
    onTextEdited: root.edited()
  }
}
