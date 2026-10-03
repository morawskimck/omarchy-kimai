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
  property alias description: descriptionField.text
  readonly property var tags: Model.mergeTags(root.selectedTags, newTagsField.text)
  readonly property bool textEditing: descriptionField.activeFocus || newTagsField.activeFocus

  signal submitted()

  spacing: Style.space(8)

  // prefill: { projectId, activityId, description, tags }
  function reset(prefill) {
    root.projectId = prefill.projectId
    root.activityId = prefill.activityId
    root.selectedTags = prefill.tags
    descriptionField.text = prefill.description
    newTagsField.text = ""
    if (!root.svc) return
    root.svc.projects(function(r) { if (r.kind === "ok") root.projectOptions = Model.toOptions(r.data) })
    root.svc.tags(function(r) { if (r.kind === "ok") root.tagOptions = Model.tagOptions(r.data) })
    root.loadActivities()
  }

  function loadActivities() {
    root.activityOptions = []
    if (!root.svc || !root.projectId) return
    var forProject = root.projectId
    root.svc.activities(forProject, function(r) {
      if (r.kind === "ok" && forProject === root.projectId) root.activityOptions = Model.toOptions(r.data)
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
      root.loadActivities()
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
    onChanged: function(value) { root.activityId = value }
  }

  TextField {
    id: descriptionField
    width: parent.width
    placeholderText: "What are you working on?"
    onAccepted: root.submitted()
  }

  MultiSelect {
    width: parent.width
    label: "Tags"
    noSelectionText: "No tags"
    options: root.tagOptions
    values: root.selectedTags
    onChanged: function(values) { root.selectedTags = values }
  }

  TextField {
    id: newTagsField
    width: parent.width
    placeholderText: "New tags, comma separated"
  }
}
