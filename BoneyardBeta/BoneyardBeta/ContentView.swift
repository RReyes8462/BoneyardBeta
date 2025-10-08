import SwiftUI
import Firebase
import FirebaseFirestore
import FirebaseAuth
import Combine

struct ContentView: View {
    // MARK: - Environment & State
    @EnvironmentObject var firebase: FirebaseManager
    @EnvironmentObject var auth: AuthManager

    @State private var climbs: [Climb] = []
    @State private var listener: ListenerRegistration?
    @State private var activeMap: String = "front"
    @State private var selectedTagFilters: Set<String> = []
    @State private var selectedSectionFilters: Set<String> = []
    @State private var showFilterSheet = false

    @State private var isEditMode = false
    @State private var selectedClimb: Climb?
    @State private var highlightedClimbID: String?
    @State private var showEditSheet = false
    @State private var showDetailSheet = false

    // Sidebar
    @State private var showSidebar = false
    @State private var showLogoutConfirm = false
    @State private var showProfile = false

    // Map transform state
    @State private var zoom: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var minFitZoom: CGFloat = 1.0

    // Layout constants
    let mapWidth: CGFloat = 1000
    let mapHeight: CGFloat = 750
    private let db = Firestore.firestore()

    // MARK: - BODY
    var body: some View {
        NavigationStack {
            ZStack(alignment: .leading) {
                // Transparent overlay to close sidebar
                if showSidebar {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation { showSidebar = false }
                        }
                        .zIndex(1)
                }

                mainContent
                    .blur(radius: showSidebar ? 5 : 0)
                    .disabled(showSidebar)

                if showSidebar {
                    sidebar
                        .transition(.move(edge: .leading))
                        .zIndex(2)
                }
            }
            .animation(.easeInOut, value: showSidebar)
            .alert("Sign Out?", isPresented: $showLogoutConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Sign Out", role: .destructive) {
                    auth.signOut()
                }
            }
        }
    }

    // MARK: - MAIN CONTENT
    private var mainContent: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {

                // MARK: - Map (Top Half)
                let topHeight = geo.size.height * 0.5

                ZStack {
                    Color.black.opacity(0.04)
                    ZStack {
                        Image(activeMap == "front" ? "ub_layout" : "ub_layout_back")
                            .resizable()
                            .frame(width: mapWidth, height: mapHeight)

                        ForEach($climbs.filter {
                            climbBinding in
                            let climb = climbBinding.wrappedValue

                            // --- Safely unwrap section ---
                            let section = climb.section?.lowercased() ?? ""

                            // --- Wall filtering based on active map ---
                            let wallMatch: Bool
                            if activeMap == "front" {
                                wallMatch = ["front", "cave", "slab", "barrel", "mural", "lil roofs", "prow", "top out", "overlap"].contains(section)
                            } else {
                                wallMatch = ["back", "roof", "curvy"].contains(section)
                            }

                            let sectionFilterMatch = selectedSectionFilters.isEmpty || selectedSectionFilters.contains(section)

                            // --- Tag filtering ---
                            let tagFilterMatch = selectedTagFilters.isEmpty || selectedTagFilters.contains(climb.grade)

                            // --- Final combined logic ---
                            return wallMatch && sectionFilterMatch && tagFilterMatch                        }) { $climb in
                            climbCircle(for: $climb)
                        }
                    }
                    .frame(width: mapWidth, height: mapHeight)
                    .scaleEffect(zoom, anchor: .center)
                    .offset(offset)
                }
                .frame(width: geo.size.width, height: topHeight, alignment: .center)
                .clipped()
                .contentShape(Rectangle())
                .overlay(alignment: .topLeading) {
                    HStack {
                        // Sidebar button
                        Button {
                            withAnimation { showSidebar.toggle() }
                        } label: {
                            Image(systemName: "line.horizontal.3")
                                .font(.system(size: 28))
                                .foregroundStyle(.primary)
                                .padding()
                        }

                        Spacer(minLength: 8)
                    }
                }

                .overlay(alignment: .topTrailing) {
                    HStack(spacing: 12) {
                        // ✅ Edit button
                        if auth.isAdmin {
                            Button {
                                isEditMode.toggle()
                            } label: {
                                Image(systemName: isEditMode ? "checkmark.circle.fill" : "pencil.circle.fill")
                                    .font(.system(size: 32))
                                    .foregroundStyle(isEditMode ? .green : .blue)
                                    .padding(.trailing, 4)
                            }

                            // ✅ Add Climb button (moved here)
                            Button {
                                let newClimb = Climb(
                                    id: nil,
                                    name: "climbName",
                                    grade: "Ungraded",
                                    color: "gray",
                                    x: 100,
                                    y: 100,
                                    gymID: "urbana boulders",
                                    ascentCount: 0,
                                    avgRating: 0,
                                    section: activeMap
                                )
                                firebase.addClimb(newClimb)
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 32))
                                    .foregroundStyle(.orange)
                                    .padding(.trailing)
                            }
                        }
                    }
                    .padding(.top, 8)
                }
                // ===================================================
                // MARK: - Map Switch Button (Bottom Left)
                // ===================================================
                .overlay(alignment: .bottomLeading) {
                    Button {
                        withAnimation {
                            activeMap = (activeMap == "front") ? "back" : "front"
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 16, weight: .semibold))
                            Text(activeMap == "front" ? "Back Wall" : "Front Wall")
                                .font(.footnote.bold())
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                        .cornerRadius(10)
                        .shadow(radius: 2)
                    }
                    .padding([.leading, .bottom], 12)
                }

                .gesture(dragGesture(in: geo))
                .gesture(magnificationGesture(in: geo))
                .onAppear {
                    listenForClimbs()
                    let fitW = geo.size.width / mapWidth
                    let fitH = (topHeight) / mapHeight
                    let fit = min(fitW, fitH)
                    minFitZoom = fit
                    zoom = fit
                    lastScale = fit
                    offset = .zero
                    lastOffset = .zero
                }
                .onChange(of: geo.size) { newSize in
                    let topH = newSize.height * 0.5
                    let fitW = newSize.width / mapWidth
                    let fitH = topH / mapHeight
                    let fit = min(fitW, fitH)
                    minFitZoom = fit
                    zoom = fit
                    lastScale = fit
                    offset = .zero
                    lastOffset = .zero
                }

                Divider()
                climbList(geo: geo)
            }
            .onDisappear { listener?.remove() }
            .sheet(isPresented: $showEditSheet) {
                if let climb = selectedClimb {
                    EditClimbView(
                        climb: climb,
                        currentMap: activeMap // 👈 pass which map is visible
                    ) { updated in
                        firebase.saveClimb(updated)
                        showEditSheet = false
                    } onDelete: {
                        firebase.deleteClimb(climb)
                        showEditSheet = false
                    }
                }
            }
            .sheet(isPresented: $showDetailSheet) {
                if let climb = selectedClimb {
                    ClimbDetailSheet(climb: climb) {
                        showDetailSheet = false
                    }
                    .environmentObject(firebase)
                    .environmentObject(auth)
                }
            }
            .sheet(isPresented: $showFilterSheet) {
                NavigationView {
                    List {
                        // =====================================================
                        // MARK: - Filter by Grade Tag
                        // =====================================================
                        Section(header: Text("Filter by Grade Tag")) {
                            Button {
                                selectedTagFilters.removeAll()
                            } label: {
                                Label("Show All Tags", systemImage: selectedTagFilters.isEmpty ? "checkmark.circle.fill" : "circle")
                            }

                            ForEach([
                                "Blue Tag (VB–V0)",
                                "Red Tag (V0–V2)",
                                "Yellow Tag (V2–4)",
                                "Green Tag (V4–6)",
                                "Purple Tag (V6–8)",
                                "Pink Tag (V8+)",
                                "White Tag (Ungraded)"
                            ], id: \.self) { tag in
                                Button {
                                    if selectedTagFilters.contains(tag) {
                                        selectedTagFilters.remove(tag)
                                    } else {
                                        selectedTagFilters.insert(tag)
                                    }
                                } label: {
                                    HStack {
                                        Text(tag)
                                        Spacer()
                                        Image(systemName: selectedTagFilters.contains(tag) ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(selectedTagFilters.contains(tag) ? .blue : .gray)
                                    }
                                }
                            }
                        }

                        // =====================================================
                        // MARK: - Filter by Section
                        // =====================================================
                        Section(header: Text("Filter by Section")) {
                            Button {
                                selectedSectionFilters.removeAll()
                            } label: {
                                Label("Show All Sections", systemImage: selectedSectionFilters.isEmpty ? "checkmark.circle.fill" : "circle")
                            }

                            ForEach(["front", "cave", "slab", "barrel", "mural", "lil roofs", "prow", "top out", "overlap", "back", "roof", "curvy"], id: \.self) { section in
                                Button {
                                    if selectedSectionFilters.contains(section) {
                                        selectedSectionFilters.remove(section)
                                    } else {
                                        selectedSectionFilters.insert(section)
                                    }
                                } label: {
                                    HStack {
                                        Text(section.capitalized)
                                        Spacer()
                                        Image(systemName: selectedSectionFilters.contains(section) ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(selectedSectionFilters.contains(section) ? .blue : .gray)
                                    }
                                }
                            }
                        }
                    }
                    .navigationTitle("Filter Climbs")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showFilterSheet = false }
                        }
                    }
                }
            }
        }
    }

    // MARK: - SIDEBAR
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            NavigationLink(destination: ProfileView().environmentObject(auth), isActive: $showProfile) {
                EmptyView()
            }

            Text("Menu")
                .font(.headline)
                .padding(.top, 40)
                .padding(.horizontal)

            Button {
                showProfile = true
                withAnimation { showSidebar = false }
            } label: {
                Label("Edit Profile", systemImage: "person.crop.circle")
                    .padding(.horizontal)
            }

            Button(role: .destructive) {
                showLogoutConfirm = true
                withAnimation { showSidebar = false }
            } label: {
                Label("Logout", systemImage: "rectangle.portrait.and.arrow.right")
                    .padding(.horizontal)
            }

            Spacer()
        }
        .frame(width: 240)
        .frame(maxHeight: .infinity)
        .background(Color(.systemGray6))
        .edgesIgnoringSafeArea(.all)
    }

    // MARK: - Individual Climb Circle
    @ViewBuilder
    private func climbCircle(for climb: Binding<Climb>) -> some View {
        Circle()
            .fill(climb.wrappedValue.colorValue)
            .frame(width: 28, height: 28)
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(highlightedClimbID == climb.wrappedValue.id ? 0.8 : 0),
                            lineWidth: 4)
                    .scaleEffect(highlightedClimbID == climb.wrappedValue.id ? 1.4 : 1)
                    .opacity(highlightedClimbID == climb.wrappedValue.id ? 0.8 : 0)
                    .animation(.easeInOut(duration: 0.4), value: highlightedClimbID)
            )
            .position(x: climb.wrappedValue.x, y: climb.wrappedValue.y)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        guard isEditMode else { return }
                        climb.wrappedValue.x = value.location.x
                        climb.wrappedValue.y = value.location.y
                    }
                    .onEnded { _ in
                        if isEditMode {
                            firebase.saveClimb(climb.wrappedValue)
                        }
                    }
            )
            .onTapGesture {
                selectedClimb = climb.wrappedValue
                if isEditMode {
                    showEditSheet = true
                }
            }
    }

    // MARK: - Climb List
    private func climbList(geo: GeometryProxy) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Climbs in Gym")
                    .font(.headline)
                    .padding(.horizontal)
                    .padding(.top, 8)
                Spacer()
                Button {
                    showFilterSheet = true
                } label: {
                    Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 22))
                        .padding(.trailing)
                }
            }

            if climbs.isEmpty {
                Text("No climbs yet.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(filteredClimbs()) { climb in
                            Button {
                                if selectedClimb?.id == climb.id {
                                    showDetailSheet = true
                                } else {
                                    centerOn(climb: climb, geo: geo)
                                }
                            } label: {
                                HStack {
                                    Circle()
                                        .fill(climb.colorValue)
                                        .frame(width: 16, height: 16)
                                    VStack(alignment: .leading) {
                                        Text(climb.name).font(.headline)
                                        Text(climb.grade)
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: selectedClimb?.id == climb.id
                                          ? "chevron.right.circle.fill"
                                          : "chevron.right.circle")
                                        .foregroundStyle(selectedClimb?.id == climb.id ? .blue : .gray)
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .frame(height: geo.size.height * 0.5)
    }
    private func filteredClimbs() -> [Climb] {
        // normalize selected sections to lowercase for comparison
        let sectionFilterSet = Set(selectedSectionFilters.map { $0.lowercased() })

        return climbs.filter { climb in
            let section = (climb.section ?? "").lowercased()

            // --- Which wall is visible for the active map? ---
            let wallMatch: Bool = (activeMap == "front")
                ? ["front", "cave", "slab"].contains(section)
                : ["back", "roof"].contains(section)

            // --- Tag filter ---
            let matchesTag = selectedTagFilters.isEmpty || selectedTagFilters.contains(climb.grade)

            // --- Section filter (user-chosen) ---
            let matchesSection = sectionFilterSet.isEmpty || sectionFilterSet.contains(section)

            return wallMatch && matchesTag && matchesSection
        }
    }
    // MARK: - Gestures
    func magnificationGesture(in geo: GeometryProxy) -> some Gesture {
        MagnificationGesture()
            .onChanged { scale in
                let newZoom = min(max(lastScale * scale, minFitZoom), 3.0)
                zoom = newZoom
                clampOffset(in: geo)
            }
            .onEnded { _ in
                lastScale = zoom
                clampOffset(in: geo)
            }
    }

    func dragGesture(in geo: GeometryProxy) -> some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
                clampOffset(in: geo)
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }

    // MARK: - Map Centering
    func centerOn(climb: Climb, geo: GeometryProxy, desiredZoom: CGFloat = 1.6) {
        selectedClimb = climb
        highlightedClimbID = climb.id

        let s = min(max(desiredZoom, minFitZoom), 3.0)
        let mapCX = mapWidth  / 2.0
        let mapCY = mapHeight / 2.0

        withAnimation(.easeInOut(duration: 0.5)) {
            zoom = s
            offset = CGSize(
                width:  (mapCX - climb.x) * s,
                height: (mapCY - climb.y) * s
            )
            clampOffset(in: geo)
            lastOffset = offset
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            highlightedClimbID = nil
        }
    }

    // MARK: - Clamp Offset
    func clampOffset(in geo: GeometryProxy) {
        let visibleWidth = geo.size.width
        let visibleHeight = geo.size.height * 0.5
        let scaledWidth = mapWidth * zoom
        let scaledHeight = mapHeight * zoom

        let maxX = max((scaledWidth - visibleWidth) / 2, 0)
        let maxY = max((scaledHeight - visibleHeight) / 2, 0)

        offset.width = min(max(offset.width, -maxX), maxX)
        offset.height = min(max(offset.height, -maxY), maxY)
    }

    // MARK: - Firestore Listener
    func listenForClimbs() {
        listener = db.collection("climbs")
            .whereField("gymID", isEqualTo: "urbana boulders")
            .addSnapshotListener { snapshot, _ in
                guard let snapshot = snapshot else { return }
                do {
                    climbs = try snapshot.documents.map { try $0.data(as: Climb.self) }
                } catch {
                    print("❌ Decode error:", error)
                }
            }
    }
}
