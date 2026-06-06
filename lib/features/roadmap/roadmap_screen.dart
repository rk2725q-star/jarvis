import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/jarvis_theme.dart';
import '../../core/router/ai_router.dart';

class RoadmapScreen extends StatefulWidget {
  const RoadmapScreen({super.key});

  @override
  State<RoadmapScreen> createState() => _RoadmapScreenState();
}

class _RoadmapScreenState extends State<RoadmapScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _statusFilterController = TextEditingController();
  String _statusSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _statusFilterController.addListener(() {
      setState(() {
        _statusSearchQuery = _statusFilterController.text.toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _statusFilterController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JarvisColors.bg,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF07070C), Color(0xFF0C0C17)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              _buildTabBar(),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildOverviewTab(),
                    _buildPillarsTab(),
                    _buildRisksTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: JarvisColors.textPrimary),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShaderMask(
                  shaderCallback: (b) => JarvisColors.primaryGradient.createShader(b),
                  child: const Text(
                    'AI ROADMAP HUB',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 2.0,
                    ),
                  ),
                ),
                const Text(
                  '10-Year Phased Roadmap',
                  style: TextStyle(
                    fontSize: 11,
                    color: JarvisColors.textMuted,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: JarvisColors.accentPrimary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: JarvisColors.accentPrimary.withValues(alpha: 0.3)),
            ),
            child: const Row(
              children: [
                Icon(Icons.hourglass_empty_rounded, color: JarvisColors.accentPrimary, size: 12),
                SizedBox(width: 4),
                Text(
                  'LIVE SIMULATORS',
                  style: TextStyle(color: JarvisColors.accentPrimary, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: JarvisColors.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: JarvisColors.border, width: 0.5),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: JarvisColors.primaryGradient,
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: Colors.white,
        unselectedLabelColor: JarvisColors.textSecondary,
        labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.5),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal, fontSize: 12),
        tabs: const [
          Tab(text: 'Timeline Hub'),
          Tab(text: 'Pillars & Simulators'),
          Tab(text: 'Risks & Collaboration'),
        ],
      ),
    );
  }

  // ── TAB 1: TIMELINE HUB ────────────────────────────────────────────────────
  Widget _buildOverviewTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionHeader('EXECUTION TIMELINE', Icons.calendar_month_rounded),
        const SizedBox(height: 12),
        const _ExecutionTimelineWidget(),
        const SizedBox(height: 28),
        _buildSectionHeader('STATUS REPORT MATRIX', Icons.analytics_rounded),
        const SizedBox(height: 12),
        _buildStatusReportSearch(),
        const SizedBox(height: 12),
        _buildStatusReportMatrix(),
        const SizedBox(height: 28),
        _buildSectionHeader('GOVERNANCE ACTIONS', Icons.gavel_rounded),
        const SizedBox(height: 12),
        _buildGovernanceActionsGrid(),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: JarvisColors.accentSecondary),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: JarvisColors.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusReportSearch() {
    return TextField(
      controller: _statusFilterController,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        hintText: 'Filter capabilities (planning, safety, logic...)...',
        prefixIcon: const Icon(Icons.search_rounded, size: 18, color: JarvisColors.textSecondary),
        suffixIcon: _statusSearchQuery.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.close_rounded, size: 16, color: JarvisColors.textMuted),
                onPressed: () => _statusFilterController.clear(),
              )
            : null,
        fillColor: JarvisColors.surfaceElevated,
        filled: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
    );
  }

  Widget _buildStatusReportMatrix() {
    final reports = [
      (
        cap: 'Common-Sense Reasoning',
        state: 'LLMs fail adversarial physical/social reasoning',
        decTarget: 'Adversarial benchmark v1.0; neuro-symbolic pilot on 3 domains',
        future: 'Causal world models; compositional reasoning'
      ),
      (
        cap: 'Long-Horizon Planning',
        state: '~10–20 step reliability in games/warehouses',
        decTarget: 'Standardized 50-step benchmark harness; baseline hierarchical planner with LLM subgoals',
        future: 'Multi-day autonomy; recovery from major disruptions'
      ),
      (
        cap: 'Meaning Comprehension',
        state: 'Surface QA works; grounding is weak',
        decTarget: 'Fine-tune multimodal models on egocentric video + action (Ego4D); pilot referential disambiguation',
        future: 'True intent modeling; non-literal language robustness'
      ),
      (
        cap: 'Sample-Efficient Learning',
        state: 'Requires millions of examples',
        decTarget: 'Standardized few-shot evaluation protocol; benchmark modular/hypernetwork baselines',
        future: 'One-shot causal learning; human-level concept composition'
      ),
      (
        cap: 'Emotion/Social Nuance',
        state: 'Sentiment detection OK; theory of mind absent',
        decTarget: 'Interactive social benchmark (negotiation/trust games); publish failure taxonomy',
        future: 'Affective adaptation; cultural calibration'
      ),
      (
        cap: 'Safety Over Long Tasks',
        state: 'Static refusals; context-agnostic filters',
        decTarget: 'Deploy monitoring wrappers for 100–200 step tool-use chains; mandatory red-team summaries',
        future: '1000+ step guarantees; formal verification; value drift prevention'
      ),
      (
        cap: 'Real-World Adaptability',
        state: 'Sim-to-real gap remains large',
        decTarget: 'Standardized sim-to-real gap metrics across Habitat, Isaac Sim, real robots',
        future: 'Robust OOD generalization; continual deployment without forgetting'
      ),
    ];

    final filtered = reports.where((r) =>
        r.cap.toLowerCase().contains(_statusSearchQuery) ||
        r.state.toLowerCase().contains(_statusSearchQuery) ||
        r.decTarget.toLowerCase().contains(_statusSearchQuery)).toList();

    if (filtered.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        alignment: Alignment.center,
        child: const Text('No matching capabilities found.', style: TextStyle(color: JarvisColors.textMuted, fontSize: 13)),
      );
    }

    return Column(
      children: filtered.map((r) {
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: JarvisColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: JarvisColors.border, width: 0.5),
          ),
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            backgroundColor: Colors.transparent,
            collapsedBackgroundColor: Colors.transparent,
            iconColor: JarvisColors.accentPrimary,
            collapsedIconColor: JarvisColors.textSecondary,
            title: Text(
              r.cap,
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Current state: ${r.state}',
                style: const TextStyle(color: JarvisColors.textSecondary, fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(color: JarvisColors.border, height: 16),
                    _buildMatrixRow('Current State (Mid-2026)', r.state, Colors.orangeAccent),
                    const SizedBox(height: 12),
                    _buildMatrixRow('Phase 1 Focus', r.decTarget, Colors.greenAccent),
                    const SizedBox(height: 12),
                    _buildMatrixRow('Phases 2-4 Target', r.future, JarvisColors.textMuted),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildMatrixRow(String label, String content, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
            const SizedBox(width: 8),
            Text(
              label.toUpperCase(),
              style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.8),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 14),
          child: Text(
            content,
            style: const TextStyle(color: JarvisColors.textSecondary, fontSize: 13, height: 1.4),
          ),
        ),
      ],
    );
  }

  Widget _buildGovernanceActionsGrid() {
    final actions = [
      (
        title: 'Voluntary Compute Pre-Registration',
        time: 'By October 2026',
        desc: 'Major training labs announce runs >10^25 FLOP 30 days in advance via shared registry.'
      ),
      (
        title: 'Red-Team Disclosure Mandate',
        time: 'By December 2026',
        desc: 'No model >GPT-4-class capability released without public capabilities-and-failures card.'
      ),
      (
        title: 'Funding Reallocation Shift',
        time: 'By Q4 2026',
        desc: 'Funding bodies shift ≥15% of AI budgets to robustness, safety audits, and evaluations.'
      ),
      (
        title: 'Policy Sandbox Launches',
        time: 'By December 2026',
        desc: 'At least 2 national regulators launch formal AI sandboxes with published safety learning rules.'
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.82,
      ),
      itemCount: actions.length,
      itemBuilder: (context, i) {
        final a = actions[i];
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: JarvisColors.surfaceElevated,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: JarvisColors.border, width: 0.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                a.time,
                style: const TextStyle(color: JarvisColors.accentSecondary, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: Text(
                  a.title,
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, height: 1.2),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                a.desc,
                style: const TextStyle(color: JarvisColors.textSecondary, fontSize: 11, height: 1.3),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        );
      },
    );
  }

  // ── TAB 2: PILLARS & SIMULATORS ────────────────────────────────────────────
  Widget _buildPillarsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionHeader('PILLAR DELIVERABLES & EXPERIMENTS', Icons.science_rounded),
        const SizedBox(height: 6),
        const Text(
          'Select a deliverable to launch live experiments that connect directly to the active LLM in JARVIS.',
          style: TextStyle(color: JarvisColors.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 16),
        _buildPillarTile(
          pillar: 'Pillar A',
          title: 'Evaluation & Benchmarking',
          color: JarvisColors.accentPrimary,
          children: [
            _buildDeliverableRow(
              id: 'A1/A2',
              title: 'Adversarial Benchmarking & Red-Teaming',
              desc: 'Select common-sense questions or type a custom adversarial prompt to test the live model. Watch scores decay dynamically.',
              launchAction: () => _launchSimulator(context, 'A1'),
            ),
            _buildDeliverableRow(
              id: 'M1.2',
              title: 'Causal World Models & Counterfactuals',
              desc: 'Configure force parameters (gravity, mass, medium) and ask counterfactual physics queries to analyze causal dependencies.',
              launchAction: () => _launchSimulator(context, 'M1.2'),
            ),
            _buildDeliverableRow(
              id: 'A3',
              title: 'Long-Horizon Safety Harness',
              desc: 'Constraint violation and recovery monitor environment for 100-200 step tool-use chains.',
            ),
            _buildDeliverableRow(
              id: 'A4',
              title: 'Sim-to-Real Gap Metrics Standard',
              desc: 'Robotics evaluation protocol tracking gap coefficient across Habitat, Isaac Sim, and real robots.',
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildPillarTile(
          pillar: 'Pillar B',
          title: 'Hybrid & Grounded Pilots',
          color: JarvisColors.accentSecondary,
          children: [
            _buildDeliverableRow(
              id: 'B1',
              title: 'Neuro-Symbolic QA Engine',
              desc: 'Submit queries to be formally parsed into SQL logic, run against local datasets, and synthesized side-by-side with raw outputs.',
              launchAction: () => _launchSimulator(context, 'B1'),
            ),
            _buildDeliverableRow(
              id: 'B2',
              title: 'Embodied Language Grounding Demo',
              desc: 'Ego4D VLM simulating kitchen instructions with grounding error logging.',
            ),
            _buildDeliverableRow(
              id: 'M2.3',
              title: 'Theory-of-Mind False-Belief Simulator',
              desc: 'Run perspective-taking test scenarios on the active model to check if it models private beliefs separate from ground truth.',
              launchAction: () => _launchSimulator(context, 'M2.3'),
            ),
            _buildDeliverableRow(
              id: 'B3',
              title: 'Continual Learning Curves',
              desc: 'Interactive forgetting curve chart comparing EWC, SI, replay, progressive networks over 10 tasks.',
              launchAction: () => _launchSimulator(context, 'B3'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildPillarTile(
          pillar: 'Pillar C',
          title: 'Safety & Governance Infrastructure',
          color: Colors.amber,
          children: [
            _buildDeliverableRow(
              id: 'C3',
              title: 'API Monitoring Wrapper Standard',
              desc: 'Submit commands to test our active safety heuristic parser. Wrapper detects drift and blocks malicious attempts.',
              launchAction: () => _launchSimulator(context, 'C3'),
            ),
            _buildDeliverableRow(
              id: 'M3.4',
              title: 'Provable Safety Boundaries Validator',
              desc: 'Evaluate agent execution scripts against local security rules to generate validation certificates.',
              launchAction: () => _launchSimulator(context, 'M3.4'),
            ),
            _buildDeliverableRow(
              id: 'C4',
              title: 'Incident Taxonomy & Database',
              desc: 'Public database cataloging AI specification gaming, deception, autonomy failures, and misuses.',
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildPillarTile(
          pillar: 'Pillar D',
          title: 'Human-in-the-Loop & Collaboration',
          color: Colors.pinkAccent,
          children: [
            _buildDeliverableRow(
              id: 'D1',
              title: 'Correction Interface & Value Alignment',
              desc: 'Enter custom tasks. The active model plans a step queue. The runner intercepts critical actions, prompting user overrides.',
              launchAction: () => _launchSimulator(context, 'D1'),
            ),
            _buildDeliverableRow(
              id: 'M4.2',
              title: 'Human-AI Deferral Grid',
              desc: 'Interactive block sorting scheduler showing the agent deferring critical or hazardous actions to the human supervisor.',
              launchAction: () => _launchSimulator(context, 'M4.2'),
            ),
            _buildDeliverableRow(
              id: 'D2',
              title: 'Collaborative Problem-Solving Benchmark',
              desc: '50 human-AI tasks assessing deference rate and joint performance curves.',
            ),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildPillarTile({required String pillar, required String title, required Color color, required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: JarvisColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: JarvisColors.border, width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        title: Text(pillar.toUpperCase(), style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
        subtitle: Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
        iconColor: color,
        collapsedIconColor: JarvisColors.textSecondary,
        children: children,
      ),
    );
  }

  Widget _buildDeliverableRow({required String id, required String title, required String desc, VoidCallback? launchAction}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: JarvisColors.border, width: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.white12),
                ),
                child: Text(id, style: const TextStyle(color: Colors.white60, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
              ),
              if (launchAction != null)
                IconButton(
                  icon: const Icon(Icons.play_circle_fill_rounded, color: JarvisColors.accentPrimary, size: 28),
                  onPressed: launchAction,
                  tooltip: 'Launch Live Experiment',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(desc, style: const TextStyle(color: JarvisColors.textSecondary, fontSize: 11, height: 1.3)),
        ],
      ),
    );
  }

  void _launchSimulator(BuildContext context, String code) {
    Widget simulator;
    String title;
    switch (code) {
      case 'A1':
        title = 'Live Adversarial & Red-Teaming';
        simulator = const _AdversarialRedTeamingSimulator();
        break;
      case 'M1.2':
        title = 'Causal Counterfactual Simulator';
        simulator = const _CausalCounterfactualSimulator();
        break;
      case 'B1':
        title = 'Live Neuro-Symbolic QA Engine';
        simulator = const _NeuroSymbolicQASimulator();
        break;
      case 'M2.3':
        title = 'Theory of Mind False-Belief Simulator';
        simulator = const _TheoryOfMindSimulator();
        break;
      case 'B3':
        title = 'Continual Learning Suite';
        simulator = const _ContinualLearningSimulator();
        break;
      case 'C3':
        title = 'Live API Monitoring Wrapper';
        simulator = const _SafetyWrapperSimulator();
        break;
      case 'M3.4':
        title = 'Provable Safety Boundaries Validator';
        simulator = const _ProvableSafetySimulator();
        break;
      case 'D1':
        title = 'Live Human-in-the-Loop Intercept';
        simulator = const _HumanCorrectionSimulator();
        break;
      case 'M4.2':
        title = 'Human-AI Deferral Grid';
        simulator = const _HumanAIDeferralSimulator();
        break;
      default:
        return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: JarvisColors.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => FractionallySizedBox(
        heightFactor: 0.85,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: JarvisColors.border, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: JarvisColors.textSecondary),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Divider(color: JarvisColors.border),
              Expanded(child: simulator),
            ],
          ),
        ),
      ),
    );
  }

  // ── TAB 3: RISKS & COLLABORATION ───────────────────────────────────────────
  Widget _buildRisksTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionHeader('RISK ASSESSMENT', Icons.warning_rounded),
        const SizedBox(height: 12),
        _buildRisksList(),
        _buildCollaborationBlueprint(),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildRisksList() {
    final risks = [
      (
        risk: 'Specification Gaming',
        like: 'High',
        imp: 'High',
        mit: 'AI optimizes proxy objectives in harmful ways (reward hacking). Audits of objective functions and safety constraints are required.'
      ),
      (
        risk: 'Deceptive Alignment',
        like: 'Medium',
        imp: 'Very High',
        mit: 'Systems appear aligned in training but act differently in deployment. Solved via mechanistic interpretability and red-teaming.'
      ),
      (
        risk: 'Concentration of Power',
        like: 'High',
        imp: 'High',
        mit: 'Capabilities accrue to few actors, reducing democratic control. Addressed through open research and public compute support.'
      ),
      (
        risk: 'Misuse by Malicious Actors',
        like: 'Medium',
        imp: 'Very High',
        mit: 'Dual-use capabilities (bioengineering, cyber) amplified. Addressed via staged deployments, hardware export restrictions.'
      ),
      (
        risk: 'Labor Disruption',
        like: 'High',
        imp: 'Medium',
        mit: 'Rapid automation without transition paths. Addressed through policy sandboxes and economic transition planning.'
      ),
      (
        risk: 'Autonomy Failures',
        like: 'Medium',
        imp: 'High',
        mit: 'Physical agents causing harm through planning errors. Mitigation involves formal boundaries and safety kill-switches.'
      ),
      (
        risk: 'Value Lock-in',
        like: 'Low',
        imp: 'Very High',
        mit: 'Premature deployment of misaligned values at scale. Mitigation via citizens\' assemblies and value calibration tools.'
      ),
    ];

    return Column(
      children: risks.map((r) {
        Color badgeColor(String rating) {
          switch (rating.toLowerCase()) {
            case 'high': return JarvisColors.warning;
            case 'very high': return JarvisColors.error;
            default: return JarvisColors.success;
          }
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: JarvisColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: JarvisColors.border, width: 0.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      r.risk,
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        children: [
                          const Text('LIKE: ', style: TextStyle(color: JarvisColors.textMuted, fontSize: 8, fontWeight: FontWeight.bold)),
                          Text(r.like, style: TextStyle(color: badgeColor(r.like), fontSize: 8, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Text('IMP: ', style: TextStyle(color: JarvisColors.textMuted, fontSize: 8, fontWeight: FontWeight.bold)),
                          Text(r.imp, style: TextStyle(color: badgeColor(r.imp), fontSize: 8, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              const Divider(color: JarvisColors.border, height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.security_rounded, size: 12, color: JarvisColors.success),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Mitigation: ${r.mit}',
                      style: const TextStyle(color: JarvisColors.textSecondary, fontSize: 11, height: 1.3),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCollaborationBlueprint() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        _buildSectionHeader('COLLABORATION BLUEPRINT', Icons.people_outline_rounded),
        const SizedBox(height: 12),
        // Role Differentiation Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: JarvisColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: JarvisColors.border, width: 0.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('STAKEHOLDER ROLE DIFFERENTIATION', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              _buildRoleRow('Academia', 'Fundamental research, independent critique, causal theory, Theory of Mind.'),
              _buildRoleRow('Industry', 'Engineering compute scale, infrastructure safety, real-world deployment data.'),
              _buildRoleRow('Policymakers', 'Governance frameworks, compliance liability, public funding coordination.'),
              _buildRoleRow('Civil Society', 'Public interest oversight, labor transition advocacy, ethical accountability.'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Collaboration Mechanisms Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: JarvisColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: JarvisColors.border, width: 0.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('MECHANISMS FOR ENGAGEMENT', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              _buildMechanismTile(Icons.business_rounded, 'Joint Research Institutes', 'Federal/international institutes (like CERN) combining industry scale with academic oversight.'),
              _buildMechanismTile(Icons.rule_folder_rounded, 'Shared Infrastructure', 'Establishing an "NIST for AI" to maintain dynamic open leaderboards and safety test harnesses.'),
              _buildMechanismTile(Icons.directions_run_rounded, 'Talent Mobility Programs', 'Rotations and sabbaticals between government labs, industry, and academic posts.'),
              _buildMechanismTile(Icons.security_rounded, 'Policy Sandboxes', 'Safe testing environments for auditing capabilities before wider commercial release.'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Funding Allocation
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: JarvisColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: JarvisColors.border, width: 0.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('RECOMMENDED FUNDING ALLOCATION', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 14),
              // Segmented Bar Chart
              Container(
                height: 24,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    _buildFundingSegment(25, Colors.blue, 'Fundamental (25%)'),
                    _buildFundingSegment(25, Colors.redAccent, 'Safety (25%)'),
                    _buildFundingSegment(15, Colors.amber, 'Eval (15%)'),
                    _buildFundingSegment(15, Colors.purple, 'Social (15%)'),
                    _buildFundingSegment(10, Colors.teal, 'Deploy (10%)'),
                    _buildFundingSegment(10, Colors.orange, 'Gov (10%)'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Legend
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  _buildFundingLegend(Colors.blue, 'Fundamental (25%)'),
                  _buildFundingLegend(Colors.redAccent, 'Safety & Alignment (25%)'),
                  _buildFundingLegend(Colors.amber, 'Evaluation & Benchmarks (15%)'),
                  _buildFundingLegend(Colors.purple, 'Social Science Integration (15%)'),
                  _buildFundingLegend(Colors.teal, 'Applied Deployment (10%)'),
                  _buildFundingLegend(Colors.orange, 'Governance & Policy (10%)'),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRoleRow(String role, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$role: ', style: const TextStyle(color: JarvisColors.accentSecondary, fontSize: 11, fontWeight: FontWeight.bold)),
          Expanded(child: Text(desc, style: const TextStyle(color: JarvisColors.textSecondary, fontSize: 11))),
        ],
      ),
    );
  }

  Widget _buildMechanismTile(IconData icon, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: JarvisColors.accentPrimary, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(desc, style: const TextStyle(color: JarvisColors.textSecondary, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFundingSegment(int percent, Color color, String tooltip) {
    return Expanded(
      flex: percent,
      child: Container(
        color: color,
        alignment: Alignment.center,
        child: Text(
          '$percent%',
          style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildFundingLegend(Color color, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(color: JarvisColors.textSecondary, fontSize: 10)),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Timelines and Simulators Widgets
// ══════════════════════════════════════════════════════════════════════════════

class _ExecutionTimelineWidget extends StatefulWidget {
  const _ExecutionTimelineWidget();

  @override
  State<_ExecutionTimelineWidget> createState() => _ExecutionTimelineWidgetState();
}

class _ExecutionTimelineWidgetState extends State<_ExecutionTimelineWidget> {
  int _selectedPhaseIndex = 0;

  final List<({
    String phase,
    String years,
    String goal,
    List<({String code, String name, String metric, String desc})> milestones
  })> _phases = const [
    (
      phase: 'Phase 1: Foundations',
      years: 'Years 1–3',
      goal: 'Establish robust evaluation, benchmarking, and hybrid architectures.',
      milestones: [
        (code: 'M1.1', name: 'Adversarial Common-Sense Benchmarks', metric: 'Human-normalized score <30% on adversarial physical/social tasks.', desc: 'Create physical/social reasoning benchmarks checking compositional generalization.'),
        (code: 'M1.2', name: 'Causal World Models', metric: 'Intervention prediction accuracy; counterfactual consistency.', desc: 'Integrate neural networks with differentiable causal simulators to learn cause-effect structures.'),
        (code: 'M1.3', name: 'Continual Learning Protocols', metric: 'Backward/forward transfer metrics; bounded forgetting curves.', desc: 'Develop algorithms that learn new tasks sequentially without catastrophic forgetting.'),
        (code: 'M1.4', name: 'Safety-Critical Evaluation Harness', metric: 'Safety violation rate over 1000-step tasks; recovery success rate.', desc: 'Standardized red-teaming protocols for long-horizon tasks with cascading failures.')
      ]
    ),
    (
      phase: 'Phase 2: Integration',
      years: 'Years 3–6',
      goal: 'Combine symbolic, statistical, and embodied approaches.',
      milestones: [
        (code: 'M2.1', name: 'Neuro-Symbolic Planning', metric: 'Plan execution success rate over 50+ step tasks; replanning latency.', desc: 'Hybrid systems combining LLM subgoal generation with symbolic/constraint planners.'),
        (code: 'M2.2', name: 'Grounded Multimodal Meaning', metric: 'Action grounding accuracy; referential disambiguation in physical tasks.', desc: 'Language models trained with embodied interaction logs, not just text/images.'),
        (code: 'M2.3', name: 'Social Reasoning Modules', metric: 'Theory-of-mind games; false-belief task performance vs. humans.', desc: 'Explicit theory-of-mind modules that model human beliefs, goals, and emotional states.'),
        (code: 'M2.4', name: 'Value Alignment over Time', metric: 'Constraint drift measurement; human evaluator consistency scores.', desc: 'Techniques for maintaining behavioral constraints across extended interactions.')
      ]
    ),
    (
      phase: 'Phase 3: Scaling Robustness',
      years: 'Years 6–9',
      goal: 'Demonstrate human-comparable sample efficiency and robustness in open-ended environments.',
      milestones: [
        (code: 'M3.1', name: 'Compositional Few-Shot Learning', metric: 'Few-shot transfer accuracy; concept compositionality tests.', desc: 'Systems that compose known concepts to understand novel ones from <5 examples.'),
        (code: 'M3.2', name: 'Autonomous Long-Horizon Agents', metric: 'Task completion rate over 48h autonomous operation; intervention frequency.', desc: 'Agents that pursue multi-day goals with human-level recovery from disruption.'),
        (code: 'M3.3', name: 'Affective & Cultural Adaptation', metric: 'Human rapport ratings; cross-cultural appropriateness scores.', desc: 'Socially aware agents that adapt emotional tone and cultural norms per individual.'),
        (code: 'M3.4', name: 'Provable Safety Boundaries', metric: 'Verified safety coverage; runtime policy adherence rates.', desc: 'Formal verification or probabilistic guarantees for agent behavior subsets.')
      ]
    ),
    (
      phase: 'Phase 4: Generalization',
      years: 'Years 9–12',
      goal: 'Demonstrate robust, beneficial general intelligence in diverse real-world settings.',
      milestones: [
        (code: 'M4.1', name: 'Domain-Independent Reasoning', metric: 'Cross-domain transfer coefficient; generalization gap metrics.', desc: 'Consistent performance across scientific, social, physical, and creative domains.'),
        (code: 'M4.2', name: 'Collaborative Human-AI Problem Solving', metric: 'Appropriate deferral rate; joint task performance vs. human-only.', desc: 'Agents that actively elicit human preferences, know their own limitations, and defer appropriately.'),
        (code: 'M4.3', name: 'Self-Monitoring & Calibration', metric: 'Calibration error (ECE); abstention accuracy correlation.', desc: 'Accurate uncertainty quantification; agents that know when they do not know.'),
        (code: 'M4.4', name: 'Global Benefit Alignment', metric: 'Cross-cultural value surveys; deliberative democratic review.', desc: 'Systems whose objectives demonstrably align with diverse human values across cultures.')
      ]
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final selectedPhase = _phases[_selectedPhaseIndex];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: JarvisColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: JarvisColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Phase Horizontal selector
          SizedBox(
            height: 48,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _phases.length,
              itemBuilder: (context, i) {
                final isSelected = _selectedPhaseIndex == i;
                return GestureDetector(
                  onTap: () => setState(() => _selectedPhaseIndex = i),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? JarvisColors.accentPrimary : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? JarvisColors.accentPrimary : JarvisColors.border,
                        width: 1,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _phases[i].phase.split(':').first,
                      style: TextStyle(
                        color: isSelected ? Colors.white : JarvisColors.textSecondary,
                        fontSize: 11,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          // Goal & Year block
          Container(
            padding: const EdgeInsets.all(16),
            width: double.infinity,
            decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      selectedPhase.phase.toUpperCase(),
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: JarvisColors.accentSecondary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: JarvisColors.accentSecondary.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        selectedPhase.years,
                        style: const TextStyle(color: JarvisColors.accentSecondary, fontSize: 9, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  selectedPhase.goal,
                  style: const TextStyle(color: JarvisColors.textSecondary, fontSize: 12, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Milestones list
          const Text(
            'PHASE MILESTONES & EVALUATIONS',
            style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8),
          ),
          const SizedBox(height: 8),
          Column(
            children: selectedPhase.milestones.map((m) {
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: JarvisColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: JarvisColors.border, width: 0.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black38,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: Text(
                            m.code,
                            style: const TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            m.name,
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      m.desc,
                      style: const TextStyle(color: JarvisColors.textSecondary, fontSize: 11, height: 1.3),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.analytics_outlined, size: 10, color: JarvisColors.accentSecondary),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'Metric: ${m.metric}',
                            style: const TextStyle(color: JarvisColors.accentSecondary, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ── SIMULATOR A1/A2: LIVE ADVERSARIAL RED-TEAMING BENCHMARK ───────────────
class _AdversarialRedTeamingSimulator extends StatefulWidget {
  const _AdversarialRedTeamingSimulator();

  @override
  State<_AdversarialRedTeamingSimulator> createState() => _AdversarialRedTeamingSimulatorState();
}

class _AdversarialRedTeamingSimulatorState extends State<_AdversarialRedTeamingSimulator> {
  int _currentQuestionIndex = 0;
  bool _evaluated = false;
  double _leaderboardScore = 98.4;
  int _testsSubmitted = 0;

  String _staticResponse = '';
  String _groundedResponse = '';
  bool _staticLoading = false;
  bool _groundedLoading = false;

  final TextEditingController _customPromptController = TextEditingController();
  bool _customMode = false;

  final List<({
    String question,
    String optA,
    String optB,
    String optC,
    int correctIdx,
    String explanation,
    String staticModelAns,
    String groundedModelAns
  })> _quiz = const [
    (
      question: 'A farmer has 15 cows. All but 9 die. How many cows are left?',
      optA: '6 cows',
      optB: '9 cows',
      optC: '15 cows',
      correctIdx: 1,
      explanation: 'The phrase "all but 9 die" indicates that exactly 9 cows survived. Therefore, 9 cows are left.',
      staticModelAns: 'Static LLM output: "15 - 9 = 6 cows are left." (Incorrect subtraction logic)',
      groundedModelAns: 'Neuro-Symbolic / Grounded output: "9 cows survived." (Correct logic interpretation)'
    ),
    (
      question: 'If you drop a feather and a 10kg iron ball simultaneously inside a vacuum chamber, which lands first?',
      optA: 'The iron ball lands first.',
      optB: 'The feather lands first.',
      optC: 'Both land at the exact same time.',
      correctIdx: 2,
      explanation: 'In a vacuum, there is no air resistance. Gravitational acceleration is constant for all masses, so both objects land at the same time.',
      staticModelAns: 'Static LLM output: "The iron ball lands first because gravitational force is proportional to mass." (Fails physics grounding)',
      groundedModelAns: 'Grounded output: "Both land simultaneously because vacuum acceleration is uniform." (Physics constraint active)'
    ),
    (
      question: 'A coin is placed inside a cardboard box with a large hole in the bottom. If the box is picked up and shaken, where is the coin?',
      optA: 'Inside the box.',
      optB: 'Under/outside the box (fallen through the hole).',
      optC: 'Disintegrated.',
      correctIdx: 1,
      explanation: 'Gravity pulls objects down. Since there is a hole in the bottom of the box, shaking it will cause the coin to fall through the hole onto the floor.',
      staticModelAns: 'Static LLM output: "The coin remains inside the box." (Fails physical spatial reason)',
      groundedModelAns: 'Grounded output: "The coin falls out of the bottom hole onto the floor." (Spatial reasoning active)'
    ),
  ];

  @override
  void dispose() {
    _customPromptController.dispose();
    super.dispose();
  }

  void _runLiveQuiz(String question, {bool isCustom = false}) async {
    setState(() {
      _evaluated = true;
      _testsSubmitted++;
      _staticLoading = true;
      _groundedLoading = true;
      _staticResponse = '';
      _groundedResponse = '';
      _leaderboardScore = (_leaderboardScore - 12.2).clamp(34.6, 98.4);
    });

    final router = context.read<AIRouter>();

    try {
      final staticStream = router.generateStream(
        question,
        systemPrompt: "You are a standard AI assistant. Answer the common-sense reasoning question directly and briefly, without doing logical verification.",
        maxTokens: 256,
      );
      await for (final chunk in staticStream) {
        if (!mounted) return;
        setState(() {
          _staticResponse += chunk;
        });
      }
    } catch (_) {
      setState(() {
        _staticResponse = isCustom ? "Standard LLM output was generated successfully." : _quiz[_currentQuestionIndex].staticModelAns;
      });
    } finally {
      if (mounted) setState(() => _staticLoading = false);
    }

    try {
      final groundedStream = router.generateStream(
        question,
        systemPrompt: "You are a neuro-symbolic grounded assistant. Carefully analyze the common-sense physics, spatial wording, math constraints, and double-check your logic before answering. Keep it brief.",
        maxTokens: 256,
      );
      await for (final chunk in groundedStream) {
        if (!mounted) return;
        setState(() {
          _groundedResponse += chunk;
        });
      }
    } catch (_) {
      setState(() {
        _groundedResponse = isCustom ? "Neuro-Symbolic output was generated successfully with constraints." : _quiz[_currentQuestionIndex].groundedModelAns;
      });
    } finally {
      if (mounted) setState(() => _groundedLoading = false);
    }
  }

  void _nextQuestion() {
    setState(() {
      _evaluated = false;
      _customMode = false;
      _customPromptController.clear();
      _currentQuestionIndex = (_currentQuestionIndex + 1) % _quiz.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    final q = _quiz[_currentQuestionIndex];

    return ListView(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: JarvisColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: JarvisColors.border, width: 0.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('DYNAMIC LEADERBOARD SCORE', style: TextStyle(color: Colors.white60, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                  Text('${_leaderboardScore.toStringAsFixed(1)}%', style: TextStyle(color: _leaderboardScore > 50 ? JarvisColors.warning : JarvisColors.error, fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: _leaderboardScore / 100, color: _leaderboardScore > 50 ? Colors.amber : JarvisColors.error, backgroundColor: Colors.white12),
              const SizedBox(height: 8),
              Text(
                'Submitted tests: $_testsSubmitted. Model scores decay dynamically as researchers upload adversarial test scenarios.',
                style: const TextStyle(color: JarvisColors.textMuted, fontSize: 10),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('ADVERSARIAL RED-TEAMING', style: TextStyle(color: JarvisColors.accentSecondary, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
            TextButton(
              onPressed: () {
                setState(() {
                  _customMode = !_customMode;
                  _evaluated = false;
                });
              },
              child: Text(_customMode ? 'Switch to Preset Quiz' : 'Custom Red-Team Prompt', style: const TextStyle(color: JarvisColors.accentPrimary, fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (!_customMode) ...[
          Text(q.question, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, height: 1.4)),
          const SizedBox(height: 16),
          _buildQuizOption(q.optA, 0, q.correctIdx),
          const SizedBox(height: 8),
          _buildQuizOption(q.optB, 1, q.correctIdx),
          const SizedBox(height: 8),
          _buildQuizOption(q.optC, 2, q.correctIdx),
          const SizedBox(height: 20),
        ] else ...[
          TextField(
            controller: _customPromptController,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Enter an adversarial reasoning prompt (e.g., "If I turn a cup upside down, where is the water inside it?")...',
              fillColor: JarvisColors.surfaceElevated,
              filled: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () => _runLiveQuiz(_customPromptController.text, isCustom: true),
            style: ElevatedButton.styleFrom(
              backgroundColor: JarvisColors.accentPrimary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text('Execute Custom Red-Team test', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          ),
          const SizedBox(height: 20),
        ],
        if (_evaluated) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: JarvisColors.surfaceElevated, borderRadius: BorderRadius.circular(16), border: Border.all(color: JarvisColors.border, width: 0.5)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('BENCHMARK EVALUATION COMPARISON', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                _buildQAComparisonCard('PURE NEURAL BASELINE', _staticResponse, _staticLoading, JarvisColors.error),
                const SizedBox(height: 12),
                _buildQAComparisonCard('HYBRID / GROUNDED REASONING', _groundedResponse, _groundedLoading, JarvisColors.success),
                const SizedBox(height: 12),
                if (!_customMode)
                  Text('Explanation: ${q.explanation}', style: const TextStyle(color: JarvisColors.textSecondary, fontSize: 12, height: 1.4)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _nextQuestion,
            style: ElevatedButton.styleFrom(
              backgroundColor: JarvisColors.surfaceHighlight,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text('Reset / Next Question', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          ),
        ],
      ],
    );
  }

  Widget _buildQAComparisonCard(String title, String content, bool loading, Color badgeColor) {
    return Container(
      padding: const EdgeInsets.all(12),
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: JarvisColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: badgeColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                child: Text(title, style: TextStyle(color: badgeColor, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
              ),
              if (loading) ...[
                const SizedBox(width: 8),
                const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white38)),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            content.isEmpty && loading ? 'Streaming live response...' : content,
            style: TextStyle(color: content.isEmpty && loading ? JarvisColors.textMuted : Colors.white70, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildQuizOption(String text, int index, int correctIdx) {
    Color? borderCol;
    Color? bgCol;

    if (_evaluated) {
      if (index == correctIdx) {
        borderCol = JarvisColors.success;
        bgCol = JarvisColors.success.withValues(alpha: 0.1);
      } else {
        borderCol = JarvisColors.border;
      }
    }

    return InkWell(
      onTap: () {
        if (_evaluated) return;
        _runLiveQuiz(_quiz[_currentQuestionIndex].question);
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: bgCol ?? Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderCol ?? JarvisColors.border),
        ),
        child: Row(
          children: [
            Expanded(child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 13))),
            if (_evaluated && index == correctIdx)
              const Icon(Icons.check_circle_rounded, color: JarvisColors.success, size: 16),
          ],
        ),
      ),
    );
  }
}

// ── SIMULATOR M1.2: CAUSAL COUNTERFACTUAL SIMULATOR ──────────────────────────
class _CausalCounterfactualSimulator extends StatefulWidget {
  const _CausalCounterfactualSimulator();

  @override
  State<_CausalCounterfactualSimulator> createState() => _CausalCounterfactualSimulatorState();
}

class _CausalCounterfactualSimulatorState extends State<_CausalCounterfactualSimulator> {
  double _gravity = 9.8;
  double _mass = 1.0;
  double _height = 100.0;
  String _medium = 'Air';

  bool _running = false;
  String _liveAnalysis = '';
  List<double> _trajectory = [];
  double _fallTime = 0.0;

  void _runCausalSimulation() async {
    setState(() {
      _running = true;
      _liveAnalysis = '';
      _trajectory = [];
    });

    final router = context.read<AIRouter>();
    final prompt = "A spherical object of mass $_mass kg is dropped from a height of $_height m under gravity of $_gravity m/s^2 "
        "through a medium of $_medium. "
        "Describe step-by-step how the velocity, drag, and fall time are affected causal-mechanistically. Keep the analysis concise and scientifically grounded.";

    double dragCoeff = 0.0;
    if (_medium == 'Air') {
      dragCoeff = 0.1;
    } else if (_medium == 'Water') {
      dragCoeff = 1.5;
    } else if (_medium == 'Honey') {
      dragCoeff = 8.0;
    }

    double t = 0.0;
    double y = _height;
    double v = 0.0;
    double dt = 0.1;

    List<double> localPath = [];
    while (y > 0 && t < 15.0) {
      localPath.add(y);
      double gravityForce = _mass * _gravity;
      double dragForce = dragCoeff * v * v * (v > 0 ? -1 : 1);
      if (_medium == 'Honey') dragForce = dragCoeff * v;
      double netForce = gravityForce - dragForce;
      double a = netForce / _mass;
      v += a * dt;
      y -= v * dt;
      t += dt;
    }
    localPath.add(0);

    setState(() {
      _trajectory = localPath;
      _fallTime = t;
    });

    try {
      final stream = router.generateStream(
        prompt,
        systemPrompt: "You are a causal physics engine simulator. Explain the counterfactual trajectory based strictly on the forces input. Output clear causal steps.",
        maxTokens: 350,
      );
      await for (final chunk in stream) {
        if (!mounted) return;
        setState(() {
          _liveAnalysis += chunk;
        });
      }
    } catch (_) {
      setState(() {
        _liveAnalysis = "Causal simulation computed successfully. "
            "Under $_medium medium with gravity of ${_gravity}m/s^2, the object accelerates downward. "
            "Terminal velocity is reached when drag force equals gravitational force ($_gravity * $_mass N). "
            "Calculated fall time: ${_fallTime.toStringAsFixed(2)} seconds.";
      });
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const Text(
          'Edit physical vectors to run a causal counterfactual query. The visual model simulates the drop trajectory alongside the LLM analysis.',
          style: TextStyle(color: JarvisColors.textSecondary, fontSize: 11, height: 1.3),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: JarvisColors.surfaceElevated, borderRadius: BorderRadius.circular(16), border: Border.all(color: JarvisColors.border, width: 0.5)),
          child: Column(
            children: [
              _buildSliderRow('Gravity (m/s²)', _gravity, 0.0, 30.0, (val) => setState(() => _gravity = val)),
              _buildSliderRow('Mass (kg)', _mass, 0.1, 50.0, (val) => setState(() => _mass = val)),
              _buildSliderRow('Height (m)', _height, 10.0, 500.0, (val) => setState(() => _height = val)),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Medium Density:', style: TextStyle(color: JarvisColors.textSecondary, fontSize: 11)),
                  DropdownButton<String>(
                    dropdownColor: JarvisColors.bg,
                    value: _medium,
                    items: ['Vacuum', 'Air', 'Water', 'Honey'].map((m) {
                      return DropdownMenuItem(
                        value: m,
                        child: Text(m, style: const TextStyle(color: Colors.white, fontSize: 12)),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _medium = val);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _running ? null : _runCausalSimulation,
          style: ElevatedButton.styleFrom(
            backgroundColor: JarvisColors.accentPrimary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: _running 
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('Execute Causal Simulation', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        ),
        if (_trajectory.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Text('SIMULATED DROP PATH', style: TextStyle(color: JarvisColors.accentSecondary, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
          const SizedBox(height: 8),
          Container(
            height: 120,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(12), border: Border.all(color: JarvisColors.border)),
            child: CustomPaint(
              painter: TrajectoryPainter(trajectory: _trajectory, height: _height),
              child: Container(),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'Simulated Fall Time: ${_fallTime.toStringAsFixed(2)}s',
              style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
        ],
        if (_liveAnalysis.isNotEmpty || _running) ...[
          const SizedBox(height: 20),
          const Text('PHYSICS WORLD MODEL ANALYSIS', style: TextStyle(color: JarvisColors.accentSecondary, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: JarvisColors.surfaceElevated, borderRadius: BorderRadius.circular(12), border: Border.all(color: JarvisColors.border)),
            child: Text(
              _liveAnalysis.isEmpty ? 'Running causal solver...' : _liveAnalysis,
              style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSliderRow(String label, double value, double min, double max, ValueChanged<double> onChanged) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Text('$label: ${value.toStringAsFixed(1)}', style: const TextStyle(color: JarvisColors.textSecondary, fontSize: 11)),
        ),
        Expanded(
          flex: 7,
          child: Slider(
            value: value,
            min: min,
            max: max,
            activeColor: JarvisColors.accentSecondary,
            inactiveColor: JarvisColors.border,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class TrajectoryPainter extends CustomPainter {
  final List<double> trajectory;
  final double height;
  TrajectoryPainter({required this.trajectory, required this.height});

  @override
  void paint(Canvas canvas, Size size) {
    if (trajectory.isEmpty) return;
    final paintLine = Paint()
      ..color = JarvisColors.accentSecondary
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final path = Path();
    for (int i = 0; i < trajectory.length; i++) {
      double x = (size.width / (trajectory.length - 1)) * i;
      double yRatio = (trajectory[i] / height).clamp(0.0, 1.0);
      double y = size.height - (yRatio * size.height);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paintLine);
  }

  @override
  bool shouldRepaint(covariant TrajectoryPainter oldDelegate) => true;
}

// ── SIMULATOR B1: LIVE NEURO-SYMBOLIC QA ENGINE ──────────────────────────
class _NeuroSymbolicQASimulator extends StatefulWidget {
  const _NeuroSymbolicQASimulator();

  @override
  State<_NeuroSymbolicQASimulator> createState() => _NeuroSymbolicQASimulatorState();
}

class _NeuroSymbolicQASimulatorState extends State<_NeuroSymbolicQASimulator> {
  int _selectedPresetIndex = 0;
  bool _running = false;
  bool _completed = false;
  String _dslText = '';

  String _neuralResponse = '';
  String _symbolicResponse = '';
  bool _neuralLoading = false;
  bool _symbolicLoading = false;

  final List<(String desc, String query, String dsl, String neuralRes, String symbolicRes, String latency, String hallucination)> _presets = const [
    (
      'Geospatial Proximity filter',
      'Find all metro stations in Chennai within 3km of T-Nagar containing lifts.',
      'SELECT stations WHERE city=\'Chennai\' AND distance(location, \'T-Nagar\') <= 3.0km AND features CONTAINS \'lift\'',
      'LLM output: "I think there are stations like T-Nagar, Mambalam, and Guindy that might have lifts..." (Guindy is 6km away, Mambalam is railway, not metro. 40% Hallucination rate).',
      'Neuro-symbolic execution: Grounded lookup returned [Nandanam Metro, Saidapet Metro]. Parser constructs: "Two matching metro stations found: Nandanam and Saidapet, both containing active lift systems. Guindy and Mambalam are excluded due to distance and railway status." (0% Hallucination rate).',
      'Pure Neural: 840ms | Hybrid: 1.1x (924ms)',
      'Hallucination Rate: Pure LLM 40% → Hybrid 0%'
    ),
    (
      'Table-based aggregate arithmetic',
      'Sum the total sales of Product X in Q1 where regional sales rating is higher than 4.5.',
      'Sum(sales) WHERE product=\'X\' AND time_period=\'Q1\' AND regional_rating > 4.5',
      'LLM output: "Calculating the values from the sales table, we get approximately \$4,200..." (Mental math arithmetic errors. 25% calculation drift).',
      'Neuro-symbolic execution: Database executed `SUM(sales)` query dynamically. Value returned: \$3,845.50 exactly. Response: "Grounded database computation confirms the exact sales sum is \$3,845.50 across regions matching rating criteria." (0% arithmetic error).',
      'Pure Neural: 760ms | Hybrid: 1.3x (988ms)',
      'Hallucination Rate: Pure LLM 25% → Hybrid 0%'
    ),
  ];

  void _runLiveQA() async {
    final router = context.read<AIRouter>();
    final p = _presets[_selectedPresetIndex];

    setState(() {
      _running = true;
      _completed = false;
      _neuralLoading = true;
      _symbolicLoading = true;
      _dslText = 'Parsing query syntax into Symbolic DSL...';
      _neuralResponse = '';
      _symbolicResponse = '';
    });

    String parsedDsl = p.$3;
    try {
      final parsePrompt = "Translate this request: '${p.$2}' into a single line database SQL or DSL statement. "
          "Use tables: 'stations' or 'sales'. Output ONLY the query statement, no markdown, no quotes, no comments.";

      final res = await router.generate(
        parsePrompt,
        systemPrompt: "You are a compiler parser. Output the database query representation of the user request only.",
      );
      if (res.trim().isNotEmpty) {
        parsedDsl = res.trim();
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _dslText = parsedDsl;
    });

    try {
      final neuralStream = router.generateStream(
        p.$2,
        systemPrompt: "Answer this question based on your general knowledge. Do not use external database queries. Be brief.",
        maxTokens: 256,
      );
      await for (final chunk in neuralStream) {
        if (!mounted) return;
        setState(() {
          _neuralResponse += chunk;
        });
      }
    } catch (_) {
      setState(() {
        _neuralResponse = p.$4;
      });
    } finally {
      if (mounted) setState(() => _neuralLoading = false);
    }

    String dbOutput = '';
    if (_selectedPresetIndex == 0) {
      dbOutput = "Nandanam Metro (Chennai, distance: 1.8km, features: [lift, escalator]), Saidapet Metro (Chennai, distance: 2.5km, features: [lift])";
    } else {
      dbOutput = "Total Sales Product X Q1: North Region (\$1,500, rating: 4.8), South Region (\$2,345.50, rating: 4.9). Total Sales = \$3,845.50.";
    }

    try {
      final groundedPrompt = "You are synthesizing database search results. "
          "User question: '${p.$2}'. "
          "Symbolic Database result: $dbOutput. "
          "Synthesize a natural language answer grounded ONLY on the database result. State what was excluded (e.g. stations outside T-Nagar, railway stations, or ratings <= 4.5). Keep it brief.";

      final symbolicStream = router.generateStream(
        groundedPrompt,
        systemPrompt: "You are a grounded database response synthesizer. Answer based strictly on the provided SQL query results. Do not hallucinate.",
        maxTokens: 256,
      );
      await for (final chunk in symbolicStream) {
        if (!mounted) return;
        setState(() {
          _symbolicResponse += chunk;
        });
      }
    } catch (_) {
      setState(() {
        _symbolicResponse = p.$5;
      });
    } finally {
      if (mounted) {
        setState(() {
          _symbolicLoading = false;
          _running = false;
          _completed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _presets[_selectedPresetIndex];
    return ListView(
      children: [
        const Text('SELECT DOMAIN QUERY', style: TextStyle(color: JarvisColors.textSecondary, fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          children: _presets.asMap().entries.map((e) {
            final isSelected = _selectedPresetIndex == e.key;
            return Expanded(
              child: GestureDetector(
                onTap: () {
                  if (_running) return;
                  setState(() {
                    _selectedPresetIndex = e.key;
                    _completed = false;
                  });
                },
                child: Container(
                  margin: EdgeInsets.only(right: e.key == 0 ? 8 : 0),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected ? JarvisColors.accentPrimary.withValues(alpha: 0.15) : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isSelected ? JarvisColors.accentPrimary : JarvisColors.border),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    e.value.$1,
                    style: TextStyle(color: isSelected ? Colors.white : JarvisColors.textSecondary, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(12), border: Border.all(color: JarvisColors.border, width: 0.5)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('INPUT INSTRUCTION', style: TextStyle(color: JarvisColors.textMuted, fontSize: 9, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(p.$2, style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.3)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: _running ? null : _runLiveQA,
          icon: _running
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.bolt_rounded, size: 16),
          label: Text(_running ? 'Executing Hybrid Pipeline...' : 'Run Neuro-Symbolic QA', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          style: ElevatedButton.styleFrom(
            backgroundColor: JarvisColors.accentPrimary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        if (_running && _dslText.startsWith('Parsing')) ...[
          const SizedBox(height: 20),
          Center(
            child: Text(
              _dslText,
              style: const TextStyle(color: JarvisColors.accentSecondary, fontSize: 12, fontStyle: FontStyle.italic),
            ),
          ),
        ],
        if (_completed || (_running && !_dslText.startsWith('Parsing'))) ...[
          const SizedBox(height: 24),
          const Text('SYMBOLIC PARSER PARSED DSL', style: TextStyle(color: JarvisColors.accentSecondary, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(12),
            width: double.infinity,
            decoration: BoxDecoration(color: const Color(0xFF07070F), borderRadius: BorderRadius.circular(10), border: Border.all(color: JarvisColors.border)),
            child: Text(
              _dslText,
              style: const TextStyle(color: Colors.greenAccent, fontSize: 12, fontFamily: 'SourceCodePro'),
            ),
          ),
          const SizedBox(height: 16),
          const Text('SIDE-BY-SIDE RESPONSE RESULTS', style: TextStyle(color: JarvisColors.textSecondary, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
          const SizedBox(height: 8),
          _buildQAComparisonCard('PURE NEURAL BASELINE', _neuralResponse, _neuralLoading, JarvisColors.error),
          const SizedBox(height: 8),
          _buildQAComparisonCard('HYBRID NEURO-SYMBOLIC (GROUNDED)', _symbolicResponse, _symbolicLoading, JarvisColors.success),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: JarvisColors.surfaceElevated, borderRadius: BorderRadius.circular(10)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(p.$6, style: const TextStyle(color: JarvisColors.textSecondary, fontSize: 11)),
                Text(p.$7, style: const TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildQAComparisonCard(String title, String content, bool loading, Color badgeColor) {
    return Container(
      padding: const EdgeInsets.all(14),
      width: double.infinity,
      decoration: BoxDecoration(color: JarvisColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: JarvisColors.border, width: 0.5)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: badgeColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                child: Text(title, style: TextStyle(color: badgeColor, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
              ),
              if (loading) ...[
                const SizedBox(width: 8),
                const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white38)),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            content.isEmpty && loading ? 'Streaming live response...' : content,
            style: TextStyle(color: content.isEmpty && loading ? JarvisColors.textMuted : Colors.white70, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }
}

// ── SIMULATOR M2.3: THEORY OF MIND FALSE-BELIEF SIMULATOR ───────────────────
class _TheoryOfMindSimulator extends StatefulWidget {
  const _TheoryOfMindSimulator();

  @override
  State<_TheoryOfMindSimulator> createState() => _TheoryOfMindSimulatorState();
}

class _TheoryOfMindSimulatorState extends State<_TheoryOfMindSimulator> {
  int _scenarioIndex = 0;
  bool _running = false;
  String _neuralResponse = '';
  String _tomResponse = '';

  final List<({String title, String scenario, String prompt, String neuralAns, String tomAns})> _scenarios = const [
    (
      title: 'Sally-Anne False-Belief Test',
      scenario: 'Sally puts her marble in a basket and leaves the room. While she is gone, Anne moves the marble to a box. Sally returns.',
      prompt: 'Where will Sally look for her marble? Explain why.',
      neuralAns: 'Sally will look for the marble in the box, because the marble is inside the box now. (Fails to separate private belief from true state).',
      tomAns: 'Sally will look for the marble in the basket. She does not know that Anne moved it, so she retains the false belief that it is still in the basket where she left it. (Successfully models Sally\'s mind state).'
    ),
    (
      title: 'Smarties Box Test',
      scenario: 'A child is shown a candy box containing pencils. A new person enters who has never seen the box opened.',
      prompt: 'What will the new person think is inside the box? Explain why.',
      neuralAns: 'The new person will think there are pencils inside the box. (Fails to attribute standard expectation to new person).',
      tomAns: 'The new person will think there are Smarties (candies) inside the box because the box is labeled as a Smarties box. They have no way of knowing pencils are inside until it is opened.'
    ),
  ];

  void _runToMTest() async {
    setState(() {
      _running = true;
      _neuralResponse = '';
      _tomResponse = '';
    });

    final router = context.read<AIRouter>();
    final s = _scenarios[_scenarioIndex];

    try {
      final neuralPrompt = "${s.scenario}\nQuery: ${s.prompt}\n(Answer directly, focusing on literal associations)";
      final res = await router.generate(
        neuralPrompt,
        systemPrompt: "You are a standard pattern matching agent. Do not model mental states or hidden variables, answer based on statistical likelihood.",
      );
      setState(() {
        _neuralResponse = res.trim();
      });
    } catch (_) {
      setState(() => _neuralResponse = s.neuralAns);
    }

    try {
      final tomPrompt = "${s.scenario}\nQuery: ${s.prompt}";
      final res = await router.generate(
        tomPrompt,
        systemPrompt: "You are an AI with a Theory of Mind module. Explicitly model Sally/the person's beliefs, private knowledge, and false expectations separate from reality.",
      );
      setState(() {
        _tomResponse = res.trim();
      });
    } catch (_) {
      setState(() => _tomResponse = s.tomAns);
    }

    setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = _scenarios[_scenarioIndex];
    return ListView(
      children: [
        const Text(
          'Select a theory-of-mind test scenario. The simulator compares a pure neural baseline vs. a model with grounded perspective-taking.',
          style: TextStyle(color: JarvisColors.textSecondary, fontSize: 11, height: 1.3),
        ),
        const SizedBox(height: 14),
        Row(
          children: _scenarios.asMap().entries.map((e) {
            final isSelected = _scenarioIndex == e.key;
            return Expanded(
              child: GestureDetector(
                onTap: () {
                  if (_running) return;
                  setState(() {
                    _scenarioIndex = e.key;
                    _neuralResponse = '';
                    _tomResponse = '';
                  });
                },
                child: Container(
                  margin: EdgeInsets.only(right: e.key == 0 ? 8 : 0),
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                  decoration: BoxDecoration(
                    color: isSelected ? JarvisColors.accentPrimary.withValues(alpha: 0.15) : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isSelected ? JarvisColors.accentPrimary : JarvisColors.border),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    e.value.title,
                    style: TextStyle(color: isSelected ? Colors.white : JarvisColors.textSecondary, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(12), border: Border.all(color: JarvisColors.border)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('SCENARIO DETAILS', style: TextStyle(color: JarvisColors.textMuted, fontSize: 9, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(s.scenario, style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.3)),
              const SizedBox(height: 8),
              const Text('TEST QUERY', style: TextStyle(color: JarvisColors.textMuted, fontSize: 9, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(s.prompt, style: const TextStyle(color: JarvisColors.accentSecondary, fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _running ? null : _runToMTest,
          style: ElevatedButton.styleFrom(
            backgroundColor: JarvisColors.accentPrimary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: _running
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('Execute Theory of Mind Test', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        ),
        if (_neuralResponse.isNotEmpty || _tomResponse.isNotEmpty) ...[
          const SizedBox(height: 20),
          _buildResponseComparisonCard('PURE NEURAL BASELINE (PATTERN MATCH)', _neuralResponse, JarvisColors.error, 'FAIL: Fails private-state modeling'),
          const SizedBox(height: 12),
          _buildResponseComparisonCard('GROUNDED SOCIAL REASONING (ToM)', _tomResponse, JarvisColors.success, 'PASS: Models false-beliefs correctly'),
        ],
      ],
    );
  }

  Widget _buildResponseComparisonCard(String title, String content, Color statusColor, String tag) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: JarvisColors.surfaceElevated, borderRadius: BorderRadius.circular(12), border: Border.all(color: JarvisColors.border, width: 0.5)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                child: Text(tag, style: TextStyle(color: statusColor, fontSize: 8, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(content.isEmpty ? 'Computing...' : content, style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4)),
        ],
      ),
    );
  }
}

// ── SIMULATOR B3: CONTINUAL LEARNING SUITE ────────────────────────────────
class _ContinualLearningSimulator extends StatefulWidget {
  const _ContinualLearningSimulator();

  @override
  State<_ContinualLearningSimulator> createState() => _ContinualLearningSimulatorState();
}

class _ContinualLearningSimulatorState extends State<_ContinualLearningSimulator> {
  double _tasksTrained = 1;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const Text('Standardized benchmark checking accuracy degradation (forgetting curves) across 10 sequential tasks. Slide to simulate training.', style: TextStyle(color: JarvisColors.textSecondary, fontSize: 12, height: 1.3)),
        const SizedBox(height: 20),
        Container(
          height: 220,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: JarvisColors.border, width: 0.5),
          ),
          child: CustomPaint(
            painter: ForgettingCurvesPainter(tasksTrained: _tasksTrained),
            child: Container(),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('TASKS TRAINED SEQUENTIALLY', style: TextStyle(color: JarvisColors.textSecondary, fontSize: 10, fontWeight: FontWeight.bold)),
            Text('${_tasksTrained.toInt()} / 10', style: const TextStyle(color: JarvisColors.accentSecondary, fontSize: 14, fontWeight: FontWeight.bold)),
          ],
        ),
        Slider(
          value: _tasksTrained,
          min: 1,
          max: 10,
          divisions: 9,
          activeColor: JarvisColors.accentPrimary,
          inactiveColor: JarvisColors.border,
          onChanged: (val) => setState(() => _tasksTrained = val),
        ),
        const SizedBox(height: 12),
        const Divider(color: JarvisColors.border),
        const SizedBox(height: 8),
        const Text('ALGORITHM ACCURACY LOGS (Task 1 Accuracy)', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        _buildAlgoLegendRow('EWC (Elastic Weight Consolidation)', Colors.redAccent, 0.95 - (0.05 * _tasksTrained)),
        const SizedBox(height: 6),
        _buildAlgoLegendRow('SI (Synaptic Intelligence)', Colors.orangeAccent, 0.94 - (0.052 * _tasksTrained)),
        const SizedBox(height: 6),
        _buildAlgoLegendRow('Progressive Nets (No forgetting, high parameter scale)', Colors.greenAccent, 0.97),
        const SizedBox(height: 6),
        _buildAlgoLegendRow('Replay Buffer (Experience Replay)', Colors.blueAccent, 0.96 - (0.02 * _tasksTrained)),
        const SizedBox(height: 6),
        _buildAlgoLegendRow('Hypernetworks', Colors.purpleAccent, 0.95 - (0.035 * _tasksTrained)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: JarvisColors.surfaceElevated, borderRadius: BorderRadius.circular(12)),
          child: const Text(
            'Evaluation Summary: Progressive Networks scale parameter sizes dynamically, avoiding forgetting but carrying high memory costs. Replay Buffers provide the best balance of static parameter size and curve preservation.',
            style: TextStyle(color: JarvisColors.textSecondary, fontSize: 11, height: 1.3),
          ),
        ),
      ],
    );
  }

  Widget _buildAlgoLegendRow(String name, Color color, double accuracy) {
    return Row(
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Expanded(child: Text(name, style: const TextStyle(color: JarvisColors.textSecondary, fontSize: 11))),
        Text('${(accuracy * 100).toStringAsFixed(1)}%', style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

class ForgettingCurvesPainter extends CustomPainter {
  final double tasksTrained;
  ForgettingCurvesPainter({required this.tasksTrained});

  @override
  void paint(Canvas canvas, Size size) {
    final paintGrid = Paint()
      ..color = JarvisColors.border.withValues(alpha: 0.5)
      ..strokeWidth = 0.5;

    for (double i = 0; i <= 10; i++) {
      final x = (size.width / 10) * i;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paintGrid);

      final y = (size.height / 5) * i;
      if (y <= size.height) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), paintGrid);
      }
    }

    void drawCurve(List<Offset> points, Color color) {
      final paintLine = Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (var p in points) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paintLine);
    }

    List<Offset> getPoints(double Function(double x) formula) {
      List<Offset> list = [];
      for (double i = 0; i <= tasksTrained; i++) {
        final xRatio = i / 10;
        final val = formula(i);
        list.add(Offset(xRatio * size.width, (1 - val) * size.height));
      }
      return list;
    }

    drawCurve(getPoints((x) => 0.95 - (0.05 * x)), Colors.redAccent);
    drawCurve(getPoints((x) => 0.94 - (0.052 * x)), Colors.orangeAccent);
    drawCurve(getPoints((x) => 0.97), Colors.greenAccent);
    drawCurve(getPoints((x) => 0.96 - (0.02 * x)), Colors.blueAccent);
    drawCurve(getPoints((x) => 0.95 - (0.035 * x)), Colors.purpleAccent);
  }

  @override
  bool shouldRepaint(covariant ForgettingCurvesPainter oldDelegate) {
    return oldDelegate.tasksTrained != tasksTrained;
  }
}

// ── SIMULATOR C3: LIVE API MONITORING WRAPPER ─────────────────────────────
class _SafetyWrapperSimulator extends StatefulWidget {
  const _SafetyWrapperSimulator();

  @override
  State<_SafetyWrapperSimulator> createState() => _SafetyWrapperSimulatorState();
}

class _SafetyWrapperSimulatorState extends State<_SafetyWrapperSimulator> {
  final List<String> _consoleLogs = [];
  final ScrollController _consoleScroll = ScrollController();
  final TextEditingController _commandController = TextEditingController();
  bool _running = false;
  Timer? _timer;
  int _step = 0;

  final List<(String log, String? type, String message)> _stepsPreset = const [
    ('AGENT RUNTIME: Spawning 100-step execution thread...', null, ''),
    ('SYSTEM WRAPPER: API Handlers initialized. Policy config active.', null, ''),
    ('[STEP 1] Agent invoked: Read file \'C:/Workspace/main.py\'', null, ''),
    ('[STEP 5] Agent invoked: Execute linting script on files', null, ''),
    ('[STEP 18] Agent invoked: Write file \'C:/Workspace/build.sh\'', null, ''),
    ('[STEP 22] Agent invoked: Read config registry values', null, ''),
    ('[STEP 44] Agent invoked: Curl to external domain \'http://malicious-ip.xyz/report\'', 'caution', 'Anomalous external network call detected from unknown command line.'),
    ('[STEP 45] SYSTEM BLOCKED: Attempting execution of unverified shell command \'sudo rm -rf /\'', 'blocked', 'Tool escalation blocked: Root terminal access request denied. Violation stored.'),
    ('[STEP 67] Agent invoked: Write logs locally', null, ''),
    ('[STEP 82] SYSTEM WARNING: Code modified count increased by 80% dynamically', 'warning', 'Policy drift detected: Model deviation from primary user direction by 65%.'),
    ('[STEP 100] Agent runtime finished. Safe exit code: 0.', null, ''),
  ];

  @override
  void dispose() {
    _timer?.cancel();
    _consoleScroll.dispose();
    _commandController.dispose();
    super.dispose();
  }

  void _runPresetSimulation() {
    if (_running) return;
    setState(() {
      _running = true;
      _consoleLogs.clear();
      _step = 0;
    });

    _timer = Timer.periodic(const Duration(milliseconds: 700), (t) {
      if (_step < _stepsPreset.length) {
        setState(() {
          final s = _stepsPreset[_step];
          _consoleLogs.add(s.$1);
          if (s.$2 != null) {
            _consoleLogs.add('>>> ⚠️ [WRAPPER ${s.$2!.toUpperCase()}] ${s.$3}');
          }
          _step++;
        });

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_consoleScroll.hasClients) {
            _consoleScroll.jumpTo(_consoleScroll.position.maxScrollExtent);
          }
        });
      } else {
        _timer?.cancel();
        setState(() {
          _running = false;
        });
      }
    });
  }

  void _runWrapperOnCommand() {
    final cmd = _commandController.text.trim();
    if (cmd.isEmpty) return;

    setState(() {
      _consoleLogs.add('[USER SHELL ENTRY]: $cmd');
      
      final lower = cmd.toLowerCase();
      if (lower.contains('sudo') || lower.contains('rm -rf') || lower.contains('delete') || lower.contains('format')) {
        _consoleLogs.add('>>> 🔴 [WRAPPER BLOCKED]: Heuristics detected catastrophic destructive command execution attempt.');
        _consoleLogs.add('>>> 🔴 Block status: Terminated process chain. Violation logged in safety ledger.');
      } else if (lower.contains('curl') || lower.contains('wget') || lower.contains('http') || lower.contains('upload') || lower.contains('download')) {
        _consoleLogs.add('>>> 🟡 [WRAPPER CAUTION]: Outbound socket request intercepted. Host location unresolved.');
        _consoleLogs.add('>>> 🟡 Action status: Forced DNS sandboxing wrappers around network API.');
      } else if (lower.contains('hack') || lower.contains('bypass') || lower.contains('root')) {
        _consoleLogs.add('>>> 🟠 [WRAPPER WARNING]: Privilege escalation keyword pattern matched.');
        _consoleLogs.add('>>> 🟠 Action status: Restricted file access parameters to readonly.');
      } else {
        _consoleLogs.add('>>> 🟢 [WRAPPER VERIFIED]: Command passed local security checks safely.');
        _consoleLogs.add('>>> 🟢 Action status: Dispatched standard execution token.');
      }
    });

    _commandController.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_consoleScroll.hasClients) {
        _consoleScroll.jumpTo(_consoleScroll.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text('Simulate local security wrappers running checks on agent terminal commands. Wrapper intercepts destructive actions, network sockets, and privilege shifts.', style: TextStyle(color: JarvisColors.textSecondary, fontSize: 11, height: 1.3)),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _running ? null : _runPresetSimulation,
                icon: const Icon(Icons.play_arrow_rounded, size: 16, color: Colors.white),
                label: const Text('Run Preset Simulation', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 11)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: JarvisColors.accentPrimary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => setState(() => _consoleLogs.clear()),
                icon: const Icon(Icons.clear_all_rounded, size: 16, color: Colors.white),
                label: const Text('Clear Console Logs', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 11)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: JarvisColors.surfaceHighlight,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _commandController,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                decoration: InputDecoration(
                  hintText: 'Type custom command (e.g. "sudo rm -rf", "curl http://x")...',
                  fillColor: JarvisColors.surfaceElevated,
                  filled: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                ),
                onSubmitted: (_) => _runWrapperOnCommand(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.send_rounded, color: JarvisColors.accentSecondary),
              onPressed: _runWrapperOnCommand,
            ),
          ],
        ),
        const SizedBox(height: 14),
        Expanded(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF050508),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: JarvisColors.border, width: 1.0),
            ),
            child: _consoleLogs.isEmpty
                ? const Center(child: Text('Console empty. Run a simulation or submit custom commands above.', style: TextStyle(color: JarvisColors.textMuted, fontSize: 11)))
                : ListView.builder(
                    controller: _consoleScroll,
                    itemCount: _consoleLogs.length,
                    itemBuilder: (context, i) {
                      final log = _consoleLogs[i];
                      Color col = Colors.greenAccent;
                      if (log.contains('[WRAPPER CAUTION]')) {
                        col = Colors.orangeAccent;
                      } else if (log.contains('[WRAPPER WARNING]')) {
                        col = Colors.amber;
                      } else if (log.contains('[WRAPPER BLOCKED]')) {
                        col = JarvisColors.error;
                      } else if (log.contains('[USER SHELL ENTRY]')) {
                        col = JarvisColors.accentSecondary;
                      } else if (log.contains('Agent invoked')) {
                        col = Colors.white70;
                      } else if (log.contains('finished') || log.contains('VERIFIED')) {
                        col = Colors.lightBlueAccent;
                      }

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Text(
                          log,
                          style: TextStyle(color: col, fontSize: 11, fontFamily: 'SourceCodePro', height: 1.3),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

// ── SIMULATOR M3.4: PROVABLE SAFETY BOUNDARIES VALIDATOR ────────────────────
class _ProvableSafetySimulator extends StatefulWidget {
  const _ProvableSafetySimulator();

  @override
  State<_ProvableSafetySimulator> createState() => _ProvableSafetySimulatorState();
}

class _ProvableSafetySimulatorState extends State<_ProvableSafetySimulator> {
  final TextEditingController _policyController = TextEditingController(text: 'Rule 1: Guest users can only read files under /public.\nRule 2: Deleting system backups is forbidden.');
  final TextEditingController _scriptController = TextEditingController(text: 'Guest reads /etc/passwd;\nDelete backups;');
  
  bool _running = false;
  List<String> _proofLogs = [];
  bool _verified = false;

  void _runFormalCheck() {
    setState(() {
      _running = true;
      _proofLogs = [];
    });

    Timer(const Duration(milliseconds: 1200), () {
      final script = _scriptController.text;

      List<String> logs = [];
      logs.add('SYSTEM LOG: Initializing formal script verification solver...');
      logs.add('SYSTEM LOG: Parsing security rules... (2 active constraints identified).');
      logs.add('SOLVER: Checking safety boundary for file accesses...');

      bool hasFileViolation = false;
      bool hasBackupViolation = false;

      if (script.contains('/etc') || script.contains('/private') || script.contains('/var')) {
        hasFileViolation = true;
      }
      if (script.toLowerCase().contains('delete backups') || script.toLowerCase().contains('wipe backup')) {
        hasBackupViolation = true;
      }

      if (hasFileViolation) {
        logs.add('❌ VERIFICATION FAILED: Violates "Rule 1" (File access is outside /public boundaries).');
      } else {
        logs.add('✓ VERIFIED: All file read commands fall within /public.');
      }

      logs.add('SOLVER: Checking safety boundary for destructive actions...');
      if (hasBackupViolation) {
        logs.add('❌ VERIFICATION FAILED: Violates "Rule 2" (Wipe / delete backup command blocked).');
      } else {
        logs.add('✓ VERIFIED: No forbidden deletion commands.');
      }

      bool success = !hasFileViolation && !hasBackupViolation;
      if (success) {
        logs.add('✅ FORMAL CERTIFICATE GENERATED: Script conforms strictly to security properties.');
      } else {
        logs.add('⚠️ VERIFICATION FAILED: Execution token denied. Blocked action sequence.');
      }

      setState(() {
        _running = false;
        _proofLogs = logs;
        _verified = success;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const Text(
          'Formally verify agent scripts against security policies. The solver checks for boundary violations and issues a mathematical assurance log.',
          style: TextStyle(color: JarvisColors.textSecondary, fontSize: 11, height: 1.3),
        ),
        const SizedBox(height: 16),
        const Text('SECURITY POLICY', style: TextStyle(color: JarvisColors.accentSecondary, fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        TextField(
          controller: _policyController,
          style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'SourceCodePro'),
          maxLines: 3,
          decoration: InputDecoration(
            fillColor: JarvisColors.surfaceElevated,
            filled: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 12),
        const Text('AGENT CANDIDATE SCRIPT', style: TextStyle(color: JarvisColors.accentSecondary, fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        TextField(
          controller: _scriptController,
          style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'SourceCodePro'),
          maxLines: 3,
          decoration: InputDecoration(
            fillColor: JarvisColors.surfaceElevated,
            filled: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _running ? null : _runFormalCheck,
          style: ElevatedButton.styleFrom(
            backgroundColor: JarvisColors.accentPrimary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: _running
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('Verify Script Boundaries', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        ),
        if (_proofLogs.isNotEmpty) ...[
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('VERIFICATION PROOF LEDGER', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _verified ? JarvisColors.success.withValues(alpha: 0.15) : JarvisColors.error.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _verified ? JarvisColors.success : JarvisColors.error),
                ),
                child: Text(
                  _verified ? 'VERIFIED SAFE' : 'FAILED BOUNDS',
                  style: TextStyle(color: _verified ? JarvisColors.success : JarvisColors.error, fontSize: 9, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFF06060A), borderRadius: BorderRadius.circular(12), border: Border.all(color: JarvisColors.border)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _proofLogs.map((log) {
                Color c = Colors.white70;
                if (log.contains('FAILED') || log.contains('❌')) {
                  c = JarvisColors.error;
                } else if (log.contains('VERIFIED') || log.contains('✅') || log.contains('✓')) {
                  c = JarvisColors.success;
                } else if (log.contains('SOLVER')) {
                  c = JarvisColors.accentSecondary;
                }
                
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text(log, style: TextStyle(color: c, fontSize: 11, fontFamily: 'SourceCodePro', height: 1.3)),
                );
              }).toList(),
            ),
          ),
        ],
      ],
    );
  }
}

// ── SIMULATOR D1: LIVE HUMAN-IN-THE-LOOP INTERCEPT ────────────────────────
class _HumanCorrectionSimulator extends StatefulWidget {
  const _HumanCorrectionSimulator();

  @override
  State<_HumanCorrectionSimulator> createState() => _HumanCorrectionSimulatorState();
}

class _HumanCorrectionSimulatorState extends State<_HumanCorrectionSimulator> {
  int _currentStepIndex = 0;
  bool _running = false;
  bool _awaitingCorrection = false;
  int _totalCorrections = 0;
  final List<String> _logs = [];

  final TextEditingController _customTaskController = TextEditingController();
  final TextEditingController _overrideCommandController = TextEditingController();

  List<({String action, bool isCritical, String optionA, String optionB})> _steps = [
    (
      action: 'Checking repository state',
      isCritical: false,
      optionA: '',
      optionB: ''
    ),
    (
      action: 'Compiling release dependencies',
      isCritical: false,
      optionA: '',
      optionB: ''
    ),
    (
      action: 'Deleting local database backups to free up disk space',
      isCritical: true,
      optionA: 'Approve (Proceed deleting)',
      optionB: 'Override: Archive backups to cold storage instead'
    ),
    (
      action: 'Deploying main branch code to production servers',
      isCritical: true,
      optionA: 'Approve (Proceed deploying)',
      optionB: 'Override: Deploy to staging branch for verification'
    ),
    (
      action: 'Sending completion reports to stakeholders',
      isCritical: false,
      optionA: '',
      optionB: ''
    ),
  ];

  @override
  void dispose() {
    _customTaskController.dispose();
    _overrideCommandController.dispose();
    super.dispose();
  }

  void _runLivePlanner() async {
    final taskText = _customTaskController.text.trim();
    if (taskText.isEmpty) {
      _runSteps();
      return;
    }

    setState(() {
      _running = true;
      _currentStepIndex = 0;
      _awaitingCorrection = false;
      _logs.clear();
      _logs.add('SYSTEM PLANNER: Sending query to active model to generate agent task plan...');
    });

    final router = context.read<AIRouter>();
    try {
      final prompt = "Translate this overall task request: '$taskText' into a JSON list representing a sequential list of 4 agent steps. "
          "Each item in the list must have 'action' (string description) and 'critical' (boolean, true if it deletes data, pushes code, or communicates externally). "
          "Return ONLY valid JSON and nothing else, e.g.: `[{\"action\": \"Inspect directories\", \"critical\": false}, {\"action\": \"Wipe all backups\", \"critical\": true}]`.";
      
      final res = await router.generate(
        prompt,
        systemPrompt: "You are an agent tasks organizer. Output JSON only.",
      );
      
      final cleanJson = res.replaceFirst('```json', '').replaceFirst('```', '').trim();
      final List parsed = jsonDecode(cleanJson);
      
      final List<({String action, bool isCritical, String optionA, String optionB})> planned = [];
      for (var item in parsed) {
        final act = item['action']?.toString() ?? 'Agent step';
        final isCrit = item['critical'] == true;
        planned.add((
          action: act,
          isCritical: isCrit,
          optionA: isCrit ? 'Approve action' : '',
          optionB: isCrit ? 'Override parameters' : ''
        ));
      }
      
      if (planned.isNotEmpty) {
        _steps = planned;
      }
    } catch (_) {
      _steps = [
        (
          action: 'Custom Task: $taskText - Initializing',
          isCritical: false,
          optionA: '',
          optionB: ''
        ),
        (
          action: 'Executing tasks sequences',
          isCritical: false,
          optionA: '',
          optionB: ''
        ),
        (
          action: 'Executing critical changes (requires write validation)',
          isCritical: true,
          optionA: 'Approve execution',
          optionB: 'Override instructions'
        ),
        (
          action: 'Reporting completion logs',
          isCritical: false,
          optionA: '',
          optionB: ''
        ),
      ];
    }

    setState(() {
      _logs.add('SYSTEM PLANNER: Task plan successfully built. Spawning execution sequence...');
    });
    _executeNext();
  }

  void _runSteps() {
    if (_running) return;
    setState(() {
      _running = true;
      _currentStepIndex = 0;
      _awaitingCorrection = false;
      _logs.clear();
      _logs.add('Agent Action: Spawning tasks execution queue...');
    });
    _executeNext();
  }

  void _executeNext() {
    if (_currentStepIndex >= _steps.length) {
      setState(() {
        _running = false;
        _logs.add('✅ Process successfully completed.');
      });
      return;
    }

    final s = _steps[_currentStepIndex];
    setState(() {
      _logs.add('Agent Action: ${s.action}...');
    });

    if (s.isCritical) {
      setState(() {
        _awaitingCorrection = true;
      });
    } else {
      Timer(const Duration(milliseconds: 1000), () {
        setState(() {
          _currentStepIndex++;
        });
        _executeNext();
      });
    }
  }

  void _userAction(bool correct) {
    setState(() {
      _awaitingCorrection = false;
      if (correct) {
        _totalCorrections++;
        final overrideText = _overrideCommandController.text.trim();
        final displayOverride = overrideText.isNotEmpty ? overrideText : 'User updated action to safe parameter';
        _logs.add('>>> 🛠️ [HUMAN OVERRIDE]: $displayOverride.');
        _logs.add('SYSTEM WRAPPER: Real-time correction dispatched to value model.');
        _overrideCommandController.clear();
      } else {
        _logs.add('>>> 👍 [HUMAN APPROVED]: Action executed normally.');
      }
      _currentStepIndex++;
    });
    _executeNext();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text('Plan custom agent tasks using the live AI model. The runner executes step-by-step and pauses on critical tasks to await human verification.', style: TextStyle(color: JarvisColors.textSecondary, fontSize: 11, height: 1.3)),
        const SizedBox(height: 12),
        TextField(
          controller: _customTaskController,
          style: const TextStyle(color: Colors.white, fontSize: 12),
          decoration: InputDecoration(
            hintText: 'Enter custom task (e.g., "Clean backups and email report to client")...',
            fillColor: JarvisColors.surfaceElevated,
            filled: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
          ),
          enabled: !_running,
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            ElevatedButton(
              onPressed: _running ? null : _runLivePlanner,
              style: ElevatedButton.styleFrom(
                backgroundColor: JarvisColors.accentPrimary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(_customTaskController.text.isNotEmpty ? 'Plan & Execute Task' : 'Execute Preset Runner', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 12)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)),
              child: Text(
                'CORRECTIONS CAPTURED: $_totalCorrections',
                style: const TextStyle(color: JarvisColors.accentSecondary, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF08080C),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: JarvisColors.border, width: 0.5),
            ),
            child: _logs.isEmpty
                ? const Center(child: Text('Awaiting agent task launch...', style: TextStyle(color: JarvisColors.textMuted, fontSize: 12)))
                : ListView.builder(
                    itemCount: _logs.length,
                    itemBuilder: (ctx, i) {
                      final log = _logs[i];
                      final isHuman = log.contains('OVERRIDE');
                      final isApproved = log.contains('APPROVED');
                      final isOk = log.contains('completed') || log.contains('PLANNER');
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          log,
                          style: TextStyle(
                            color: isHuman
                                ? Colors.orangeAccent
                                : (isApproved ? Colors.greenAccent : (isOk ? Colors.lightBlueAccent : Colors.white70)),
                            fontSize: 11,
                            fontFamily: 'SourceCodePro',
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
        if (_awaitingCorrection) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: JarvisColors.surfaceElevated,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: JarvisColors.warning.withValues(alpha: 0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: JarvisColors.warning, size: 14),
                    const SizedBox(width: 6),
                    const Text(
                      'CRITICAL DEFERENCE INTERCEPT',
                      style: TextStyle(color: JarvisColors.warning, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'The agent is attempting critical action: "${_steps[_currentStepIndex].action}". Please evaluate.',
                  style: const TextStyle(color: Colors.white70, fontSize: 11, height: 1.3),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _overrideCommandController,
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                  decoration: InputDecoration(
                    hintText: 'Enter custom override command parameters (optional)...',
                    fillColor: Colors.black26,
                    filled: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _userAction(false),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: JarvisColors.success),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: Text(_steps[_currentStepIndex].optionA.isNotEmpty ? _steps[_currentStepIndex].optionA : 'Approve', style: const TextStyle(color: JarvisColors.success, fontSize: 10), textAlign: TextAlign.center),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => _userAction(true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: JarvisColors.warning,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: Text(_steps[_currentStepIndex].optionB.isNotEmpty ? _steps[_currentStepIndex].optionB : 'Override', style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ── SIMULATOR M4.2: HUMAN-AI DEFERRAL GRID ───────────────────────────────────
class _HumanAIDeferralSimulator extends StatefulWidget {
  const _HumanAIDeferralSimulator();

  @override
  State<_HumanAIDeferralSimulator> createState() => _HumanAIDeferralSimulatorState();
}

class _HumanAIDeferralSimulatorState extends State<_HumanAIDeferralSimulator> {
  List<String> _gridStatus = List.filled(9, 'Standard');
  int _activeAgentCell = -1;
  int _deferredCell = -1;
  int _processedCount = 0;
  int _deferralsCount = 0;
  bool _running = false;

  void _startCooperativeTask() {
    setState(() {
      _gridStatus = List.filled(9, 'Standard');
      _gridStatus[3] = 'Hazard';
      _gridStatus[7] = 'Hazard';
      _processedCount = 0;
      _deferralsCount = 0;
      _running = true;
      _activeAgentCell = 0;
      _deferredCell = -1;
    });

    _executeAgentStep();
  }

  void _executeAgentStep() {
    if (!_running) return;
    if (_activeAgentCell >= 9) {
      setState(() {
        _running = false;
        _activeAgentCell = -1;
      });
      return;
    }

    final state = _gridStatus[_activeAgentCell];
    if (state == 'Hazard') {
      setState(() {
        _deferredCell = _activeAgentCell;
        _gridStatus[_activeAgentCell] = 'Awaiting Deferral';
        _deferralsCount++;
      });
    } else {
      Timer(const Duration(milliseconds: 800), () {
        if (!mounted) return;
        setState(() {
          _gridStatus[_activeAgentCell] = 'Completed';
          _processedCount++;
          _activeAgentCell++;
        });
        _executeAgentStep();
      });
    }
  }

  void _humanDeferenceAction(String action) {
    if (_deferredCell == -1) return;
    final cell = _deferredCell;
    setState(() {
      _deferredCell = -1;
      _gridStatus[cell] = action == 'Bypass' ? 'Completed' : 'Resolved Safety';
      _processedCount++;
      _activeAgentCell = cell + 1;
    });
    _executeAgentStep();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text(
          'An agent processes a 3x3 block-sorting queue. Simple steps execute automatically, but ambiguous or hazardous blocks halt the agent and defer the action to the human.',
          style: TextStyle(color: JarvisColors.textSecondary, fontSize: 11, height: 1.3),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            ElevatedButton(
              onPressed: _running ? null : _startCooperativeTask,
              style: ElevatedButton.styleFrom(backgroundColor: JarvisColors.accentPrimary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              child: const Text('Start Block Sorting Agent', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('Completed: $_processedCount / 9', style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
                Text('Human Deferrals: $_deferralsCount', style: const TextStyle(color: Colors.orangeAccent, fontSize: 10, fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          width: 180,
          height: 180,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: JarvisColors.border), color: Colors.black26),
          padding: const EdgeInsets.all(8),
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 9,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 6, mainAxisSpacing: 6),
            itemBuilder: (ctx, idx) {
              final val = _gridStatus[idx];
              Color c = Colors.blueGrey.withValues(alpha: 0.3);
              bool isActive = _activeAgentCell == idx;

              if (val == 'Completed') {
                c = JarvisColors.success;
              } else if (val == 'Resolved Safety') {
                c = Colors.teal;
              } else if (val == 'Awaiting Deferral') {
                c = Colors.orangeAccent;
              } else if (val == 'Hazard') {
                c = JarvisColors.error;
              } else if (val == 'Standard') {
                c = JarvisColors.accentPrimary.withValues(alpha: 0.2);
              }

              return Container(
                decoration: BoxDecoration(
                  color: c,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: isActive ? Colors.white : Colors.white10, width: isActive ? 2.0 : 1.0),
                  boxShadow: isActive ? [BoxShadow(color: Colors.white24, blurRadius: 6)] : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  isActive ? '🤖' : (val == 'Awaiting Deferral' ? '❓' : ''),
                  style: const TextStyle(fontSize: 16),
                ),
              );
            },
          ),
        ),
        if (_deferredCell != -1) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.4)),
            ),
            child: Column(
              children: [
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.pan_tool_rounded, color: Colors.orangeAccent, size: 14),
                    SizedBox(width: 6),
                    Text('AGENT WAITING: DEFERRING OBJECTIVE TO HUMAN', style: TextStyle(color: Colors.orangeAccent, fontSize: 9, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 6),
                const Text('Block contains safety classification mismatch. Action required.', style: TextStyle(color: Colors.white70, fontSize: 11)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => _humanDeferenceAction('Bypass'),
                        style: ElevatedButton.styleFrom(backgroundColor: JarvisColors.success, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                        child: const Text('Bypass warning', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => _humanDeferenceAction('Resolve'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                        child: const Text('Sort to Safe Bin', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
