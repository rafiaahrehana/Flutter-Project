import 'package:flutter_test/flutter_test.dart';
import 'package:zuhoo/features/crm/crm_models.dart';

/// CRM is where a quiet bug costs money rather than time: a deal that cannot be
/// closed, a lost reason the backend rejects, or a duplicate client created
/// because a request was assembled wrong. None of these announce themselves.
void main() {
  Opportunity deal({
    String stage = Stage.qualification,
    int? clientId,
    String? expectedCloseDate,
  }) =>
      Opportunity(
        id: 1,
        name: 'Annual licence renewal',
        stage: stage,
        probability: 40,
        createdAt: '2026-08-01T10:00:00',
        clientId: clientId,
        expectedCloseDate: expectedCloseDate,
      );

  Lead lead({
    String status = LeadStatus.isNew,
    bool converted = false,
    String? companyName,
    String? lastContactDate,
    String? lastActivityAt,
  }) =>
      Lead(
        id: 1,
        contactName: 'Rehana Akter',
        status: status,
        source: 'REFERRAL',
        createdAt: '2026-08-01T10:00:00',
        converted: converted,
        companyName: companyName,
        lastContactDate: lastContactDate,
        lastActivityAt: lastActivityAt,
      );

  group('Stage', () {
    test('the pipeline is the open stages only', () {
      expect(Stage.open, hasLength(4));
      expect(Stage.open, isNot(contains(Stage.won)));
      expect(Stage.open, isNot(contains(Stage.lost)));
      expect(Stage.isClosed(Stage.won), isTrue);
      expect(Stage.isClosed(Stage.lost), isTrue);
    });

    test('stages stay in pipeline order', () {
      // The detail screen derives "advance to next" by index, so a reorder
      // here would quietly send deals to the wrong stage.
      expect(Stage.open, [
        Stage.qualification,
        Stage.presentation,
        Stage.proposal,
        Stage.negotiation,
      ]);
    });
  });

  group('Opportunity', () {
    test('open and closed are decided by stage', () {
      expect(deal().isOpen, isTrue);
      expect(deal(stage: Stage.negotiation).isOpen, isTrue);
      expect(deal(stage: Stage.won).isOpen, isFalse);
      expect(deal(stage: Stage.won).isWon, isTrue);
      expect(deal(stage: Stage.lost).isLost, isTrue);
    });

    test('winning a client-less deal needs a decision first', () {
      // This is what triggers the duplicate check: the backend has to be told
      // whether to create a client or attach an existing one.
      expect(deal().needsClientDecisionOnWin, isTrue);
      expect(deal(clientId: 12).needsClientDecisionOnWin, isFalse);
    });

    test('overdue means open and past its close date', () {
      final past = DateTime.now().subtract(const Duration(days: 3));
      final future = DateTime.now().add(const Duration(days: 3));
      String iso(DateTime d) =>
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

      expect(deal(expectedCloseDate: iso(past)).isOverdue, isTrue);
      expect(deal(expectedCloseDate: iso(future)).isOverdue, isFalse);
      expect(deal().isOverdue, isFalse, reason: 'no date, nothing to be late for');

      // A closed deal is never overdue — it is done, whenever it happened.
      expect(
        deal(stage: Stage.won, expectedCloseDate: iso(past)).isOverdue,
        isFalse,
      );
    });

    test('parses an amount sent as an int', () {
      final parsed = Opportunity.fromJson(const {
        'id': 3,
        'name': 'Deal',
        'stage': 'PROPOSAL',
        'probability': 60,
        'createdAt': '2026-08-01T10:00:00',
        'amount': 50000,
        'weightedAmount': 30000,
      });
      expect(parsed.amount, 50000.0);
      expect(parsed.weightedAmount, 30000.0);
    });
  });

  group('ChangeStageRequest', () {
    test('a plain move sends only the stage', () {
      final json = const ChangeStageRequest(stage: Stage.proposal).toJson();
      expect(json, {'stage': Stage.proposal});
    });

    test('a loss carries its reason code', () {
      final json = const ChangeStageRequest(
        stage: Stage.lost,
        lostReasonCode: 'PRICE',
      ).toJson();
      expect(json['lostReasonCode'], 'PRICE');
      expect(json.containsKey('lostReason'), isFalse);
    });

    test('OTHER carries the free text as well', () {
      final json = const ChangeStageRequest(
        stage: Stage.lost,
        lostReasonCode: 'OTHER',
        lostReason: '  Went with an in-house build  ',
      ).toJson();
      expect(json['lostReasonCode'], 'OTHER');
      expect(json['lostReason'], 'Went with an in-house build');
    });

    test('the two win outcomes are mutually exclusive on the wire', () {
      final link = const ChangeStageRequest(
        stage: Stage.won,
        linkToExistingClientId: 7,
      ).toJson();
      expect(link['linkToExistingClientId'], 7);
      expect(link.containsKey('forceCreateNewClient'), isFalse);

      final create = const ChangeStageRequest(
        stage: Stage.won,
        forceCreateNewClient: true,
      ).toJson();
      expect(create['forceCreateNewClient'], isTrue);
      expect(create.containsKey('linkToExistingClientId'), isFalse,
          reason: 'sending both would leave the backend to guess which won');
    });
  });

  group('Lead', () {
    test('only a qualified, unconverted lead can be converted', () {
      expect(lead(status: LeadStatus.qualified).canConvert, isTrue);
      expect(lead(status: LeadStatus.isNew).canConvert, isFalse);
      expect(lead(status: LeadStatus.contacted).canConvert, isFalse);
      expect(lead(status: LeadStatus.disqualified).canConvert, isFalse);
      expect(
        lead(status: LeadStatus.qualified, converted: true).canConvert,
        isFalse,
        reason: 'converting twice would create a second opportunity',
      );
    });

    test('never contacted needs both signals absent', () {
      expect(lead().neverContacted, isTrue);
      expect(lead(lastContactDate: '2026-08-02').neverContacted, isFalse);
      expect(lead(lastActivityAt: '2026-08-02T09:00:00').neverContacted, isFalse);
    });

    test('the company is the headline when there is one', () {
      // A rep scans a list by account, not by person.
      final withCompany = lead(companyName: 'Dhrubotara Ltd');
      expect(withCompany.headline, 'Dhrubotara Ltd');
      expect(withCompany.subline, 'Rehana Akter');

      final withoutCompany = lead();
      expect(withoutCompany.headline, 'Rehana Akter');
    });

    test('a blank company name does not become the headline', () {
      final blank = lead(companyName: '   ');
      expect(blank.headline, 'Rehana Akter');
    });
  });

  group('CreateLeadRequest', () {
    test('omits blank optionals instead of sending empty strings', () {
      final json = const CreateLeadRequest(
        contactName: '  Rehana  ',
        source: 'REFERRAL',
        companyName: '   ',
        email: '',
      ).toJson();

      expect(json['contactName'], 'Rehana');
      expect(json.containsKey('companyName'), isFalse);
      expect(json.containsKey('email'), isFalse);
      expect(json.containsKey('estimatedValue'), isFalse);
    });
  });

  group('Tag', () {
    test('parses hex colours, long and short', () {
      expect(const Tag(id: 1, name: 'VIP', color: '#FF0000').argb, 0xFFFF0000);
      expect(const Tag(id: 1, name: 'VIP', color: 'FF0000').argb, 0xFFFF0000);
      expect(const Tag(id: 1, name: 'VIP', color: '#F00').argb, 0xFFFF0000);
    });

    test('an unparseable colour yields null rather than throwing', () {
      // The chip falls back to a neutral tone. Dropping the tag, or crashing
      // the list, would both be worse than the wrong colour.
      expect(const Tag(id: 1, name: 'VIP', color: '').argb, isNull);
      expect(const Tag(id: 1, name: 'VIP', color: 'red').argb, isNull);
      expect(const Tag(id: 1, name: 'VIP', color: '#GGGGGG').argb, isNull);
    });
  });

  group('DuplicateMatch', () {
    test('needs a client id to be a match at all', () {
      expect(DuplicateMatch.tryFrom(null), isNull);
      expect(DuplicateMatch.tryFrom(const {}), isNull);
      expect(DuplicateMatch.tryFrom('nope'), isNull);

      final match = DuplicateMatch.tryFrom(const {
        'clientId': 5,
        'clientCompanyName': 'Dhrubotara Ltd',
        'matchedOn': 'EMAIL',
      });
      expect(match, isNotNull);
      expect(match!.clientId, 5);
    });
  });

  group('PipelineSummary', () {
    test('finds a stage, and returns null for one that is absent', () {
      final summary = PipelineSummary.fromJson(const {
        'openPipelineValue': 100000,
        'weightedForecast': 42000,
        'totalOpenDeals': 6,
        'stages': [
          {'stage': 'PROPOSAL', 'dealCount': 2, 'totalAmount': 40000, 'weightedAmount': 20000},
        ],
      });

      expect(summary.totalOpenDeals, 6);
      expect(summary.forStage('PROPOSAL')?.dealCount, 2);
      expect(summary.forStage('NEGOTIATION'), isNull);
    });
  });
}
