import SwiftUI
import SwiftData
import KoiShared

struct TodoView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var model = TodoViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KoiTheme.space.s34) {
                header
                if !model.showingArchive { modePicker }
                if model.showingArchive { archiveContent }
                else {
                    habitsSection
                    if model.mode == .list { listContent } else { matrixContent }
                }
            }
            .padding(.horizontal, KoiTheme.space.s21)
            .padding(.top, KoiTheme.space.s21)
            .padding(.bottom, KoiTheme.space.s34)
        }
        .scrollIndicators(.hidden)
        .onAppear { model.load(modelContext) }
        .sheet(isPresented: Binding(get: { model.showingNewTask }, set: { if !$0 { model.cancelNewTask() } })) { NewTaskSheet(model: model) }
        .sheet(isPresented: Binding(get: { model.showingNewHabit }, set: { if !$0 { model.cancelNewHabit() } })) { NewHabitSheet(model: model) }
        .alert("Keep this for later?", isPresented: Binding(get: { model.staleTaskID != nil }, set: { if !$0 { model.dismissStaleTask(keep: true) } })) {
            Button("Keep", role: .cancel) { model.dismissStaleTask(keep: true) }
            Button("Let go", role: .destructive) { model.dismissStaleTask(keep: false) }
        } message: { Text("This someday to-do has been quiet for a week.") }
        .alert("Couldn't save", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "Try again.") }
        .overlay(alignment: .top) {
            if model.autoUrgentMessage != nil {
                HStack(spacing: 8) {
                    Text(model.autoUrgentMessage ?? "")
                    Spacer(minLength: 8)
                    Button("Undo") { if let id = model.toastTaskID, let task = model.tasks.first(where: { $0.id == id }) { model.undoAutoUrgent(task) } }
                        .underline()
                    Button { model.dismissAutoUrgent() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Dismiss")
                }
                .font(KoiTheme.caption)
                .padding(13)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(KoiTheme.onBase.opacity(0.3)))
                .padding(.horizontal, 21).padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 13) {
            VStack(alignment: .leading, spacing: 5) {
                Text("TO-DO").font(KoiTheme.section).tracking(2.4).foregroundStyle(KoiTheme.onBase.opacity(0.8))
                Text(model.showingArchive ? "A quiet place." : "One thing at a time.")
                    .font(KoiTheme.title).foregroundStyle(KoiTheme.onBase)
            }
            Spacer(minLength: 2)
            Button { model.toggleArchive() } label: {
                Image(systemName: model.showingArchive ? "arrow.uturn.backward" : "archivebox")
                    .font(.system(size: 18, weight: .light)).foregroundStyle(KoiTheme.onBase)
                    .frame(width: 42, height: 42).contentShape(Circle())
            }
            .accessibilityLabel(model.showingArchive ? "Close archive" : "Archive")
        }
    }

    private var modePicker: some View {
        HStack(spacing: 8) {
            ForEach(TodoMode.allCases) { mode in
                Button { withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) { model.setMode(mode) } } label: {
                    GlassChip(title: mode.rawValue, symbol: mode == .list ? "list.bullet" : "square.grid.2x2", isOn: model.mode == mode)
                }.buttonStyle(.plain)
            }
            Spacer()
            Button { model.beginHabit() } label: { Label("Habit", systemImage: "plus") }.buttonStyle(QuietTextButtonStyle())
        }
    }

    private var habitsSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                sectionLabel("HABITS")
                Spacer()
                Button { model.beginHabit() } label: { Text("+ New habit") }.buttonStyle(QuietTextButtonStyle())
            }
            if model.activeHabits.isEmpty {
                Text("A few steady rituals help the day take shape.")
                    .font(KoiTheme.body).foregroundStyle(KoiTheme.onBase.opacity(0.75))
                Button("Start a habit") { model.beginHabit() }.buttonStyle(QuietTextButtonStyle())
            } else {
                ForEach(model.activeHabits) { habit in
                    VStack(spacing: 0) {
                        HStack(spacing: 13) {
                            Button { model.toggleHabit(habit) } label: { CheckCircle(isOn: model.todayCompletion(for: habit) > 0) }
                                .buttonStyle(.plain).accessibilityLabel("Check in: \(habit.title)")
                            Button { model.openHabit(habit) } label: {
                                HStack(spacing: 5) {
                                    Text(habit.title).font(KoiTheme.body)
                                    if !habit.identity.isEmpty { Text("· Part of you").font(KoiTheme.caption).foregroundStyle(KoiTheme.onBase.opacity(0.7)) }
                                }.foregroundStyle(KoiTheme.onBase).frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(.plain)
                            Text(scheduleLabel(habit)).font(KoiTheme.caption).foregroundStyle(KoiTheme.onBase.opacity(0.68))
                        }.frame(minHeight: 42)
                        if model.selectedHabitID == habit.id { habitDetail(habit) }
                        Rectangle().fill(KoiTheme.divider.opacity(0.6)).frame(height: 0.5)
                    }
                }
            }
        }
    }

    private var listContent: some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s21) {
            sectionLabel("TO-DOS")
            if model.pendingTasks.isEmpty {
                Text("Nothing waiting. Leave room for the day.").font(KoiTheme.body).foregroundStyle(KoiTheme.onBase.opacity(0.75))
            }
            ForEach(TodoSection.allCases) { section in
                let rows = model.tasks(in: section)
                if !rows.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) { Text(section.title.uppercased()).tracking(1.3); Text("· \(rows.count)") }
                            .font(KoiTheme.section).foregroundStyle(KoiTheme.onBase.opacity(0.72))
                        ForEach(rows) { taskRow($0, compact: false) }
                    }
                }
            }
            if !model.finishedTasks.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("DONE TODAY")
                    ForEach(model.finishedTasks) { taskRow($0, compact: true) }
                }
            }
            KoiPrimaryButton(title: "Add a to-do") { model.beginTask() }
        }
    }

    private var matrixContent: some View {
        VStack(alignment: .leading, spacing: 13) {
            sectionLabel("FOCUS MATRIX")
            HStack(spacing: 0) {
                Text("URGENT").font(KoiTheme.section).tracking(1.2).frame(maxWidth: .infinity)
                Text("GIVE IT TIME").font(KoiTheme.section).tracking(1.2).frame(maxWidth: .infinity)
            }.foregroundStyle(KoiTheme.onBase.opacity(0.72))
            HStack(alignment: .top, spacing: 8) {
                matrixColumn([.urgentImportant, .urgentNotImportant])
                matrixColumn([.notUrgentImportant, .someday])
            }
            KoiPrimaryButton(title: "Add a to-do") { model.beginTask() }
        }
    }

    private func matrixColumn(_ sections: [TodoSection]) -> some View {
        VStack(spacing: 8) {
            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text(section.title.uppercased()).font(KoiTheme.section).tracking(1); Spacer(); Text("\(model.count(in: section))").font(KoiTheme.caption) }
                        .foregroundStyle(KoiTheme.onBase.opacity(0.82))
                    if model.tasks(in: section).isEmpty {
                        Text("A little space").font(KoiTheme.caption).foregroundStyle(KoiTheme.onBase.opacity(0.58)).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                    } else {
                        ForEach(model.tasks(in: section)) { task in
                            taskRow(task, compact: true)
                                .draggable(task.id.uuidString)
                        }
                    }
                }
                .padding(13)
                .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
                .background(.ultraThinMaterial.opacity(0.28), in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(KoiTheme.onBase.opacity(0.22)))
                .dropDestination(for: String.self) { values, _ in
                    guard let id = values.first.flatMap(UUID.init(uuidString:)), let task = model.tasks.first(where: { $0.id == id }) else { return false }
                    model.move(task, to: section); return true
                }
            }
        }
    }

    private func taskRow(_ task: KoiTask, compact: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 13) {
                Button { model.toggleCompletion(task) } label: { CheckCircle(isOn: task.isComplete) }
                    .buttonStyle(.plain).accessibilityLabel(task.isComplete ? "Reopen \(task.title)" : "Complete \(task.title)")
                Button { model.openTask(task) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(task.title).font(KoiTheme.body).strikethrough(task.isComplete).foregroundStyle(KoiTheme.onBase).lineLimit(2)
                        if !compact, let due = model.dueLabel(for: task) { Text(due).font(KoiTheme.caption).foregroundStyle(KoiTheme.onBase.opacity(0.68)) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain)
                if model.tasksMarkedUrgent.contains(task.id) { Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .light)).foregroundStyle(KoiTheme.onBase.opacity(0.72)) }
            }.frame(minHeight: 44)
            if model.selectedTaskID == task.id { taskDetail(task) }
            Rectangle().fill(KoiTheme.divider.opacity(0.6)).frame(height: 0.5)
        }
        .contextMenu {
            ForEach(TodoSection.allCases) { section in Button("Move to \(section.title)") { model.move(task, to: section) } }
            Button("Delete", role: .destructive) { model.deleteTask(task) }
        }
        .simultaneousGesture(DragGesture(minimumDistance: 28).onEnded { value in
            if value.translation.width > 100 { model.toggleCompletion(task) }
            else if value.translation.width < -100 { model.deleteTask(task) }
        })
    }

    private func taskDetail(_ task: KoiTask) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 8) { ForEach(TodoSection.allCases) { section in Button { model.move(task, to: section) } label: { GlassChip(title: section.title, isOn: model.currentSection(for: task) == section) }.buttonStyle(.plain) } }
            Button(task.dueAt == nil ? "Add a due date" : "Remove due date") {
                if task.dueAt == nil { model.setDueDate(task, date: .now) } else { model.setDueDate(task, date: nil) }
            }.buttonStyle(QuietTextButtonStyle())
            if task.dueAt != nil {
                DatePicker("Due", selection: Binding(get: { task.dueAt ?? .now }, set: { model.setDueDate(task, date: $0) }), displayedComponents: [.date, .hourAndMinute])
                    .font(KoiTheme.caption).tint(KoiTheme.onBase).foregroundStyle(KoiTheme.onBase)
            }
            if let note = task.notes.nilIfBlank { Text(note).font(KoiTheme.body).foregroundStyle(KoiTheme.onBase.opacity(0.8)) }
            if task.urgentOverride == false && model.isUrgent(task) == false { Text("Marked not urgent").font(KoiTheme.caption).foregroundStyle(KoiTheme.onBase.opacity(0.7)) }
            HStack {
                Button("Edit") { model.beginEditingTask(task) }.buttonStyle(QuietTextButtonStyle())
                Spacer()
                Button("Archive") { model.archiveTask(task) }.buttonStyle(QuietTextButtonStyle())
            }
        }.padding(.vertical, 13)
    }

    private func habitDetail(_ habit: KoiHabit) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !habit.note.isEmpty { Text(habit.note).font(KoiTheme.body).foregroundStyle(KoiTheme.onBase.opacity(0.78)) }
            Text("Schedule · \(scheduleLabel(habit))").font(KoiTheme.caption).foregroundStyle(KoiTheme.onBase.opacity(0.75))
            if let time = habit.reminderTime { Text("Reminder · \(time.formatted(date: .omitted, time: .shortened))").font(KoiTheme.caption).foregroundStyle(KoiTheme.onBase.opacity(0.75)) }
            if !habit.minimumVersion.isEmpty { Button("Minimum · \(habit.minimumVersion)") { model.toggleHabit(habit, minimum: true) }.buttonStyle(QuietTextButtonStyle()) }
            if !habit.stackingCue.isEmpty { Text("After \(habit.stackingCue)").font(KoiTheme.caption).foregroundStyle(KoiTheme.onBase.opacity(0.75)) }
            HStack {
                Button("Edit") { model.beginEditingHabit(habit) }.buttonStyle(QuietTextButtonStyle())
                Spacer()
                Button("Pause habit") { model.pauseHabit(habit) }.buttonStyle(QuietTextButtonStyle())
            }
        }.padding(.vertical, 8)
    }

    private var archiveContent: some View {
        VStack(alignment: .leading, spacing: KoiTheme.space.s21) {
            sectionLabel("FINISHED TO-DOS")
            ForEach(model.archivedTasks) { task in archiveRow(task.title) { model.restoreTask(task) } }
            ForEach(model.finishedTasks) { task in
                if task.completedAt.map({ $0 < (Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now) }) == true {
                    archiveRow(task.title) { model.restoreTask(task) }
                }
            }
            sectionLabel("PAUSED HABITS")
            ForEach(model.pausedHabits) { habit in archiveRow(habit.title) { model.restoreHabit(habit) } }
            if model.archivedTasks.isEmpty && model.pausedHabits.isEmpty && model.finishedTasks.isEmpty { Text("The archive is clear.").font(KoiTheme.body).foregroundStyle(KoiTheme.onBase.opacity(0.75)) }
        }
    }

    private func archiveRow(_ title: String, restore: @escaping () -> Void) -> some View {
        HStack { Text(title).font(KoiTheme.body).foregroundStyle(KoiTheme.onBase); Spacer(); Button("Restore", action: restore).buttonStyle(QuietTextButtonStyle()) }
            .frame(minHeight: 44).overlay(alignment: .bottom) { Rectangle().fill(KoiTheme.divider).frame(height: 0.5) }
    }

    private func sectionLabel(_ text: String) -> some View { Text(text).font(KoiTheme.section).tracking(2.4).foregroundStyle(KoiTheme.onBase.opacity(0.78)) }
    private func scheduleLabel(_ habit: KoiHabit) -> String {
        if habit.schedule == "weekly" { return "Weekly" }
        if habit.schedule == "monthly" { return "Monthly" }
        if habit.schedule == "someDays" {
            let names = habit.weekdays.compactMap { weekdayName($0) }
            return names.isEmpty ? "Some days" : names.joined(separator: " · ")
        }
        return "Daily"
    }
    private func weekdayName(_ value: Int) -> String? {
        let symbols = Calendar.current.shortWeekdaySymbols
        guard (1...symbols.count).contains(value) else { return nil }
        return symbols[value - 1]
    }
}

private struct NewTaskSheet: View {
    @Bindable var model: TodoViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var titleFocused: Bool
    private let prompts = ["What needs doing?", "On your mind?", "One thing…", "What's next?"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 21) {
                    TextField(prompts[Int(Date.now.timeIntervalSince1970 / 86400) % prompts.count], text: Binding(get: { model.taskDraft.title }, set: { value in model.updateTaskTitle(value) }), axis: .vertical)
                        .font(.custom("RobotoMono-Light", size: 24)).foregroundStyle(KoiTheme.onBase).lineLimit(2...4).focused($titleFocused)
                    if let parsed = model.parsedTitleDate {
                        Button { model.ignoreParsedDate() } label: { GlassChip(title: parsedDateLabel(parsed), symbol: "calendar", isOn: true) }.buttonStyle(.plain)
                    }
                    VStack(alignment: .leading, spacing: 13) {
                        Text("WHERE IT BELONGS").font(KoiTheme.section).tracking(2).foregroundStyle(KoiTheme.onBase.opacity(0.76))
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(TodoSection.allCases) { section in
                                Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) { model.chooseTaskQuadrant(section) } } label: {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(section.title).font(KoiTheme.body)
                                        Text("\(section.hint) · \(model.count(in: section)) here").font(KoiTheme.caption).opacity(0.72)
                                    }.foregroundStyle(KoiTheme.onBase)
                                        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading).padding(13)
                                        .background(model.taskDraft.hasChosenQuadrant && model.taskDraft.quadrant == section ? AnyShapeStyle(.ultraThinMaterial.opacity(0.65)) : AnyShapeStyle(.ultraThinMaterial.opacity(0.28)), in: RoundedRectangle(cornerRadius: 16))
                                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(KoiTheme.onBase.opacity(model.taskDraft.hasChosenQuadrant && model.taskDraft.quadrant == section ? 0.68 : 0.28)))
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("WHEN").font(KoiTheme.section).tracking(2).foregroundStyle(KoiTheme.onBase.opacity(0.76))
                        HStack(spacing: 8) {
                            Button { model.chooseTaskDate(nil) } label: { GlassChip(title: "No date", isOn: model.taskDraft.dueAt == nil) }.buttonStyle(.plain)
                            Button { model.chooseTaskDate(model.taskDraft.dueAt ?? .now) } label: { GlassChip(title: "Pick a day", symbol: "calendar", isOn: model.taskDraft.dueAt != nil) }.buttonStyle(.plain)
                        }
                        if model.taskDraft.dueAt != nil {
                    DatePicker(model.taskDraft.hasTime ? "Day and time" : "Day", selection: Binding(get: { model.taskDraft.dueAt ?? .now }, set: { model.chooseTaskDate($0) }), displayedComponents: model.taskDraft.hasTime ? [.date, .hourAndMinute] : [.date])
                        .font(KoiTheme.body).tint(KoiTheme.onBase).foregroundStyle(KoiTheme.onBase)
                    Button(model.taskDraft.hasTime ? "Remove time" : "Add a time") { model.setTaskHasTime(!model.taskDraft.hasTime) }
                        .buttonStyle(QuietTextButtonStyle())
                        }
                    }
                    HStack { Text("+ Note").font(KoiTheme.caption).foregroundStyle(KoiTheme.onBase); Spacer() }
                    TextField("A note, if it helps", text: Binding(get: { model.taskDraft.notes }, set: { model.taskDraft.notes = $0 }), axis: .vertical)
                        .font(KoiTheme.body).foregroundStyle(KoiTheme.onBase).lineLimit(2...5)
                    KoiPrimaryButton(title: buttonTitle) { model.saveTask(); if !model.showingNewTask { dismiss() } }
                        .disabled(!model.canSaveTask).opacity(model.canSaveTask ? 1 : 0.52)
                }.padding(21)
            }
            .background(KoiBackground().ignoresSafeArea())
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { model.cancelNewTask(); dismiss() }.foregroundStyle(KoiTheme.onBase) } }
        }
        .presentationDetents([.large]).preferredColorScheme(.dark)
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { titleFocused = true } }
    }

    private var buttonTitle: String {
        let date = model.taskDraft.dueAt.map { " · \(taskDueLabel($0))" } ?? ""
        if model.editingTaskID != nil { return "Save changes\(date)" }
        return "Add to \(model.taskDraft.quadrant.title)\(date)"
    }

    private func parsedDateLabel(_ parsed: ParsedDate) -> String {
        taskDueLabel(parsed.date)
    }

    private func taskDueLabel(_ date: Date) -> String {
        let day: String
        if Calendar.current.isDateInToday(date) { day = "today" }
        else if Calendar.current.isDateInTomorrow(date) { day = "tomorrow" }
        else { day = date.formatted(.dateTime.weekday(.abbreviated)) }
        return !model.taskDraft.hasTime ? day : "\(day) at \(date.formatted(date: .omitted, time: .shortened))"
    }
}

private struct NewHabitSheet: View {
    @Bindable var model: TodoViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var titleFocused: Bool
    private let days: [(String, Int)] = [("M", 2), ("T", 3), ("W", 4), ("T", 5), ("F", 6), ("S", 7), ("S", 1)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 21) {
                    TextField("What would you like to make a habit?", text: Binding(get: { model.habitDraft.title }, set: { model.habitDraft.title = $0 }), axis: .vertical)
                        .font(.custom("RobotoMono-Light", size: 24)).foregroundStyle(KoiTheme.onBase).lineLimit(2...4).focused($titleFocused)
                    TextField("+ Note", text: Binding(get: { model.habitDraft.note }, set: { model.habitDraft.note = $0 }))
                        .font(KoiTheme.body).foregroundStyle(KoiTheme.onBase)
                    VStack(alignment: .leading, spacing: 13) {
                        Text("HOW OFTEN").font(KoiTheme.section).tracking(2).foregroundStyle(KoiTheme.onBase.opacity(0.76))
                        HStack(spacing: 6) { scheduleChip("Daily", "daily"); scheduleChip("Weekly", "weekly"); scheduleChip("Some days", "someDays"); scheduleChip("Monthly", "monthly") }
                        if model.habitDraft.schedule == "someDays" {
                            HStack(spacing: 8) { ForEach(days, id: \.1) { title, day in Button { if model.habitDraft.weekdays.contains(day) { model.habitDraft.weekdays.remove(day) } else { model.habitDraft.weekdays.insert(day) } } label: { GlassChip(title: title, isOn: model.habitDraft.weekdays.contains(day)) }.buttonStyle(.plain) } }
                        }
                    }
                    VStack(alignment: .leading, spacing: 13) {
                        Text("WHEN").font(KoiTheme.section).tracking(2).foregroundStyle(KoiTheme.onBase.opacity(0.76))
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                            timeChip("Any time", nil)
                            timeChip("Morning · 8", 8)
                            timeChip("Midday · 12", 12)
                            timeChip("Evening · 7", 19)
                            exactTimeChip
                        }
                        if model.habitDraft.usesExactReminderTime {
                            DatePicker("Reminder time", selection: Binding(get: { reminderDate }, set: { value in
                                model.setReminderTime(hour: Calendar.current.component(.hour, from: value), minute: Calendar.current.component(.minute, from: value), exact: true)
                            }), displayedComponents: .hourAndMinute)
                            .font(KoiTheme.body).tint(KoiTheme.onBase).foregroundStyle(KoiTheme.onBase)
                        }
                    }
                    TextField("Two-minute version (optional)", text: Binding(get: { model.habitDraft.minimumVersion }, set: { model.habitDraft.minimumVersion = $0 }))
                        .font(KoiTheme.body).foregroundStyle(KoiTheme.onBase)
                    TextField("After I…", text: Binding(get: { model.habitDraft.stackingCue }, set: { model.habitDraft.stackingCue = $0 }))
                        .font(KoiTheme.body).foregroundStyle(KoiTheme.onBase)
                    TextField("Who you're becoming (optional)", text: Binding(get: { model.habitDraft.identity }, set: { model.habitDraft.identity = $0 }))
                        .font(KoiTheme.body).foregroundStyle(KoiTheme.onBase)
                    KoiPrimaryButton(title: habitButtonTitle) { model.saveHabit(); if !model.showingNewHabit { dismiss() } }
                        .disabled(!model.canSaveHabit).opacity(model.canSaveHabit ? 1 : 0.52)
                }.padding(21)
            }
            .background(KoiBackground().ignoresSafeArea())
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { model.cancelNewHabit(); dismiss() }.foregroundStyle(KoiTheme.onBase) } }
        }
        .presentationDetents([.large]).preferredColorScheme(.dark)
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { titleFocused = true } }
    }

    private var habitButtonTitle: String {
        let schedule = model.habitDraft.schedule == "someDays" ? "some days" : model.habitDraft.schedule
        let time = model.habitDraft.reminderHour.map { " · \(Calendar.current.date(from: DateComponents(hour: $0, minute: 0))?.formatted(date: .omitted, time: .shortened) ?? "")" } ?? ""
        return "\(model.editingHabitID == nil ? "Start" : "Save") · \(schedule)\(time)"
    }
    private func scheduleChip(_ title: String, _ value: String) -> some View { Button { model.habitDraft.schedule = value } label: { GlassChip(title: title, isOn: model.habitDraft.schedule == value) }.buttonStyle(.plain) }
    private var reminderDate: Date {
        Calendar.current.date(from: DateComponents(hour: model.habitDraft.reminderHour ?? 8, minute: model.habitDraft.reminderMinute)) ?? .now
    }
    private var exactTimeChip: some View {
        Button { model.setReminderTime(hour: model.habitDraft.reminderHour ?? 8, minute: model.habitDraft.reminderMinute, exact: true) } label: {
            GlassChip(title: "Exact time", isOn: model.habitDraft.usesExactReminderTime)
        }.buttonStyle(.plain)
    }
    private func timeChip(_ title: String, _ hour: Int?) -> some View { Button { model.setReminderTime(hour: hour, minute: 0) } label: { GlassChip(title: title, isOn: model.habitDraft.reminderHour == hour && !model.habitDraft.usesExactReminderTime) }.buttonStyle(.plain) }
}

private struct CheckCircle: View {
    let isOn: Bool
    var body: some View {
        Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 21, weight: .light)).foregroundStyle(KoiTheme.onBase.opacity(isOn ? 0.96 : 0.68))
            .frame(width: 32, height: 32).contentTransition(.symbolEffect(.replace))
    }
}

private struct QuietTextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(KoiTheme.caption).foregroundStyle(KoiTheme.onBase.opacity(configuration.isPressed ? 0.55 : 0.9)).padding(.vertical, 5)
    }
}

private extension String {
    var nilIfBlank: String? { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self }
}
