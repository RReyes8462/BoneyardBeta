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

    @State private var isEditMode = false
    @State private var selectedClimb: Climb?
    @State private var highlightedClimbID: String?
    @State private var showEditSheet = false
    @State private var showDetailSheet = false

    // Map transform state
    @State private var zoom: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var minFitZoom: CGFloat = 1.0   // computed dynamically

    // Layout constants
    let mapWidth: CGFloat = 1000
    let mapHeight: CGFloat = 750
    private let db = Firestore.firestore()

    // MARK: - BODY
    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {

                // MARK: - Map (Top Half; fully clipped)
                let topHeight = geo.size.height * 0.5

                ZStack {
                    // Optional subtle bg
                    Color.black.opacity(0.04)

                    // The canvas that scales/offsets
                    ZStack {
                        Image("ub_layout")
                            .resizable()
                            .frame(width: mapWidth, height: mapHeight)

                        ForEach($climbs) { $climb in
                            climbCircle(for: $climb)
                        }
                    }
                    .frame(width: mapWidth, height: mapHeight)
                    .scaleEffect(zoom, anchor: .center)
                    .offset(offset)
                }
                .frame(width: geo.size.width, height: topHeight, alignment: .center)
                .clipped() // ✅ hard clip to top half
                .contentShape(Rectangle()) // ✅ gestures confined to top half
                .overlay(alignment: .topTrailing) {
                    if auth.isAdmin {
                        Button {
                            isEditMode.toggle()
                        } label: {
                            Image(systemName: isEditMode ? "checkmark.circle.fill" : "pencil.circle.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(isEditMode ? .green : .blue)
                                .padding()
                        }
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if auth.isAdmin {
                        Button {
                            firebase.addClimb(gymID: "urbana boulders", updatedBy: auth.user?.email ?? "Unknown")
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(.orange)
                                .padding()
                        }
                    }
                }
                .gesture(dragGesture(in: geo))
                .gesture(magnificationGesture(in: geo))
                .onAppear {
                    listenForClimbs()

                    // compute fit using the actual top-half height
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

                // MARK: - Bottom Half (Climb List)
                climbList(geo: geo)
            }
            .onDisappear { listener?.remove() }
            .sheet(isPresented: $showEditSheet) {
                if let climb = selectedClimb {
                    EditClimbView(climb: climb) { updated in
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
        }
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
                Button(action: { auth.signOut() }) {
                    Image(systemName: "rectangle.portrait.and.arrow.right.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.blue)
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
                        ForEach(climbs) { climb in
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

        let targetZoom = min(max(desiredZoom, minFitZoom), 3.0)
        let viewCenter = CGPoint(x: geo.size.width / 2,
                                 y: (geo.size.height * 0.5) / 2)
        let contentCenter = CGPoint(x: mapWidth / 2, y: mapHeight / 2)
        let point = CGPoint(x: climb.x, y: climb.y)

        // offset so the climb is centered in the visible top-half viewport
        let dx = viewCenter.x - (contentCenter.x + targetZoom * (point.x - contentCenter.x))
        let dy = viewCenter.y - (contentCenter.y + targetZoom * (point.y - contentCenter.y))
        let newOffset = CGSize(width: dx, height: dy)

        withAnimation(.easeInOut(duration: 0.5)) {
            zoom = targetZoom
            offset = newOffset
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
